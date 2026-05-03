const express = require('express');
const mysql = require('mysql2/promise');
const cors = require('cors');
const path = require('path');
const multer = require('multer');
const sharp = require('sharp');
const fs = require('fs');
const bcrypt = require('bcrypt');

const app = express();
app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// --- 1. CONFIGURACIÓN DE RUTAS (AJUSTADO PARA LINUX/GOOGLE CLOUD) ---
// En Linux no usamos C:\. Usaremos una carpeta en tu home de usuario.
const rutaFotos = path.join(__dirname, 'uploads'); 

if (!fs.existsSync(rutaFotos)) {
    fs.mkdirSync(rutaFotos, { recursive: true });
}

app.use('/uploads', express.static(rutaFotos));

// --- CONFIGURACIÓN DE MULTER ---
const storage = multer.diskStorage({
    destination: function (req, file, cb) {
        cb(null, rutaFotos);
    },
    filename: function (req, file, cb) {
        const clave = req.body.clave || 'temp';
        cb(null, `${clave}-${Date.now()}${path.extname(file.originalname)}`);
    }
});
const upload = multer({ storage: storage });

// --- 2. CONFIGURACIÓN DE BASE DE DATOS (Mantenemos localhost para Google Cloud) ---
const db = mysql.createPool({
    host: '127.0.0.1',
    user: 'root',
    password: 'ADMIN', // <-- Asegúrate que sea la misma contraseña de tu MariaDB en la nube
    database: 'Factory',
    dateStrings: true,
    timezone: '+00:00',
    supportBigNumbers: true,
    bigNumberStrings: true,
});

// Auxiliar para cálculos financieros
function calcularValores(precio, costo) {
    const p = parseFloat(precio) || 0;
    const c = parseFloat(costo) || 0;
    if (p === 0) return { utilidad: 0, porutil: 0 };
    const utilidad = p - c;
    const porutil = (c > 0) ? (utilidad / c) * 100 : 0;
    return { utilidad, porutil };
}

// ==========================================
// RUTAS DE PRODUCTOS Y STOCK
// ==========================================

app.get('/api/producto/stock-actual', async (req, res) => {
    const { p_id, num_suc } = req.query;
    try {
        const sql = `
            SELECT 
                p.Min1, 
                IFNULL(a.ExisPVentas, 0) as stock_disponible
            FROM productos p
            LEFT JOIN alm${num_suc} a ON p.Clave = a.Clave
            WHERE p.Id = ?`;
            
        const [results] = await db.execute(sql, [p_id]);
        
        if (results.length > 0) {
            res.json(results[0]);
        } else {
            res.json({ Min1: 1, stock_disponible: 0 });
        }
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

app.get('/api/config/api_url', async (req, res) => {
    try {
        const [rows] = await db.execute(
            "SELECT valor FROM app_config WHERE clave = 'api_url' LIMIT 1"
        );
        if (rows.length > 0) {
            res.json(rows[0]);
        } else {
            res.status(404).json({ error: "No configurado" });
        }
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

// ==========================================
// RUTA DE SUBIDA CON SHARP (CORREGIDA)
// ==========================================
app.post('/api/producto/upload-foto', upload.single('foto'), async (req, res) => {
    const { clave } = req.body;
    if (!req.file) return res.status(400).json({ success: false, message: 'No se subió archivo' });

    try {
        const rutaOriginal = req.file.path;
        const nombreFinal = `${clave}-${Date.now()}.jpg`;
        const rutaFinal = path.join(rutaFotos, nombreFinal);

        await sharp(rutaOriginal)
            .resize(800, null, { withoutEnlargement: true, fit: 'inside' })
            .jpeg({ 
                quality: 80, 
                progressive: true, // Corregido: true en minúscula
                mozjpeg: true      // Corregido: true en minúscula
            })
            .toFile(rutaFinal);

        if (fs.existsSync(rutaOriginal)) fs.unlinkSync(rutaOriginal); 

        const [rows] = await db.execute('SELECT Foto FROM productos WHERE Clave = ?', [clave]);
        if (rows.length > 0 && rows[0].Foto) {
            const viejaPath = path.join(rutaFotos, rows[0].Foto);
            if (fs.existsSync(viejaPath)) try { fs.unlinkSync(viejaPath); } catch(e) {}
        }

        await db.execute('UPDATE productos SET Foto = ? WHERE Clave = ?', [nombreFinal, clave]);
        res.json({ success: true, foto: nombreFinal });

    } catch (e) {
        res.status(500).json({ success: false, message: e.message });
    }
});

app.post('/api/producto/delete-foto', async (req, res) => {
    const { clave } = req.body;
    try {
        const [rows] = await db.execute('SELECT Foto FROM productos WHERE Clave = ?', [clave]);
        if (rows.length > 0 && rows[0].Foto) {
            const fotoPath = path.join(rutaFotos, rows[0].Foto);
            if (fs.existsSync(fotoPath)) fs.unlinkSync(fotoPath);
            
            // IMPORTANTE: Limpiamos tanto la Foto local como el drive_id 
            // para que la App sepa que ya no hay imagen.
            await db.execute('UPDATE productos SET Foto = NULL, drive_id = NULL WHERE Clave = ?', [clave]);
        }
        res.json({ success: true });
    } catch (e) {
        res.status(500).json({ success: false, message: e.message });
    }
});

// ==========================================
// CONSULTA DE INVENTARIO (CON DRIVE_ID PARA LA APP)
// ==========================================
app.get('/api/inventario', async (req, res) => {
    const qRaw = req.query.q || '';
    const page = parseInt(req.query.page) || 0; 
    const idSuc = req.query.idSuc || 1; 
    const seed = req.query.seed || 1;
    const limit = 10; 
    const offset = page * limit;
    
    try {
        const camposSelect = `
            p.Id, p.Clave, p.Descripcion, p.product_desc, p.Precio1, p.Precio2, p.Precio3, 
            p.Min1, p.Min2, p.Min3, p.Foto, p.drive_id, p.Tipo, p.status, p.Activo,
            CAST(a.ExisPVentas AS SIGNED) as stock_disponible
        `;

        let query;
        let params;

        if (qRaw === '') {
            query = `SELECT ${camposSelect}
                     FROM productos p
                     INNER JOIN alm${idSuc} a ON p.Clave = a.Clave
                     WHERE p.status = 1 AND a.ExisPVentas > 0
                     ORDER BY RAND(${seed}) 
                     LIMIT ? OFFSET ?`;
            params = [limit, offset];
        } else {
            const searchPattern = `%${qRaw.trim()}%`;
            query = `SELECT ${camposSelect}
                     FROM productos p
                     INNER JOIN alm${idSuc} a ON p.Clave = a.Clave
                     WHERE p.status = 1 AND a.ExisPVentas > 0
                     AND (p.Descripcion LIKE ? OR p.Clave LIKE ? OR p.Tipo LIKE ?)
                     ORDER BY (p.Descripcion LIKE ?) DESC, p.Descripcion ASC 
                     LIMIT ? OFFSET ?`;
            params = [searchPattern, searchPattern, searchPattern, `${qRaw.trim()}%`, limit, offset];
        }

        const [results] = await db.execute(query, params);
        res.json(results);
    } catch (e) { 
        res.status(500).json({ error: e.message }); 
    }
});

// RUTA INDIVIDUAL (CON DRIVE_ID)
app.get('/api/producto/:clave', async (req, res) => {
    const { clave } = req.params;
    const query = `
        SELECT p.*, p.drive_id,
               a1.ExisPVentas AS alm1_pventas, a2.ExisPVentas AS alm2_pventas, 
               a3.ExisPVentas AS alm3_pventas, a4.ExisPVentas AS alm4_pventas, 
               a5.ExisPVentas AS alm5_pventas 
        FROM productos p 
        LEFT JOIN alm1 a1 ON p.Clave = a1.Clave
        LEFT JOIN alm2 a2 ON p.Clave = a2.Clave
        LEFT JOIN alm3 a3 ON p.Clave = a3.Clave
        LEFT JOIN alm4 a4 ON p.Clave = a4.Clave
        LEFT JOIN alm5 a5 ON p.Clave = a5.Clave
        WHERE p.Clave = ?`;

    try {
        const [results] = await db.execute(query, [clave]);
        res.json(results[0] || {}); 
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

// RUTA PARA VACIAR EL CARRITO (Necesaria para el botón de la App)
app.post('/api/carrito/vaciar', async (req, res) => {
    const { ip_add } = req.body;
    try {
        await db.execute("DELETE FROM cart WHERE ip_add = ?", [ip_add || 'APP_USER']);
        res.json({ success: true, message: "Carrito vaciado correctamente" });
    } catch (e) {
        console.error("Error al vaciar carrito:", e.message);
        res.status(500).json({ success: false, error: e.message });
    }
});

//finalizar pedido
// FINALIZAR PEDIDO: Mueve del carrito a pending_orders
// FINALIZAR PEDIDO: Con validación de stock de último segundo
app.post('/api/finalizar_pedido', async (req, res) => {
    const { ip_add, customer_id, num_suc } = req.body;
    const user_ip = ip_add || 'APP_USER';
    const tablaAlm = `alm${num_suc}`; 
    const invoice_no = Math.floor(Date.now() / 1000); 

    let conn;
    try {
        conn = await db.getConnection();
        await conn.beginTransaction(); 

        // --- NUEVO: OBTENER WHATSAPP DE LA SUCURSAL ---
        const [empresaData] = await conn.execute(
            "SELECT TelefonoWhatsapp FROM empresa WHERE Id = ?",
            [num_suc]
        );
        const whatsappDestino = empresaData[0]?.TelefonoWhatsapp || "";

        // 1. Obtener productos del carrito
        const [cartItems] = await conn.execute(
            `SELECT c.p_id, c.qty, c.p_price, p.Clave, p.Descripcion 
             FROM cart c 
             JOIN productos p ON c.p_id = p.Id 
             WHERE c.ip_add = ?`, 
            [user_ip]
        );

        if (cartItems.length === 0) {
            await conn.rollback();
            return res.status(400).json({ success: false, message: "El carrito está vacío" });
        }

        // 2. VALIDACIÓN DE STOCK REAL
        for (const item of cartItems) {
            const [stockData] = await conn.execute(
                `SELECT ExisPVentas FROM ${tablaAlm} WHERE Clave = ?`, 
                [item.Clave]
            );

            const existenciaActual = stockData[0]?.ExisPVentas || 0;

            if (existenciaActual < item.qty) {
                await conn.rollback();
                return res.status(400).json({ 
                    success: false, 
                    error: "SIN_STOCK",
                    message: `Stock insuficiente para: ${item.Descripcion}. Disponible: ${existenciaActual}, Solicitado: ${item.qty}` 
                });
            }
        }

        // 3. Inserción en pending_orders
        for (const item of cartItems) {
            await conn.execute(
                `INSERT INTO pending_orders 
                (customer_id, invoice_no, product_id, qty, p_price, order_status, order_date, num_suc) 
                VALUES (?, ?, ?, ?, ?, 'PENDIENTE', NOW(), ?)`,
                [customer_id || 0, invoice_no, item.p_id, item.qty, item.p_price, num_suc]
            );
        }

        // 4. Vaciamos el carrito
        await conn.execute("DELETE FROM cart WHERE ip_add = ?", [user_ip]);

        await conn.commit(); 

        // 5. RESPUESTA FINAL CON EL TELÉFONO
        res.json({ 
            success: true, 
            message: "¡Pedido verificado y guardado!", 
            invoice_no: invoice_no,
            whatsapp_phone: whatsappDestino 
        });

    } catch (e) {
        if (conn) await conn.rollback();
        console.error("Error crítico en finalizar_pedido:", e.message);
        res.status(500).json({ success: false, error: e.message });
    } finally {
        if (conn) conn.release();
    }
});

// --- 1. OBTENER PERFIL DEL CLIENTE (GET) ---
// --- ACTUALIZAR PERFIL DEL CLIENTE (COINCIDENCIA EXACTA CON FLUTTER) ---
// --- 1. OBTENER DATOS DEL PERFIL (Esta es la que quita el círculo al entrar) ---
app.get('/api/cliente/perfil', async (req, res) => {
    const { id } = req.query;
    console.log("🔎 Consultando datos para el cliente ID:", id);

    if (!id) return res.status(400).json({ success: false, message: "Falta ID" });

    try {
        const [rows] = await db.execute("SELECT * FROM clientes WHERE Id = ?", [id]);
        
        if (rows.length === 0) {
            return res.status(404).json({ success: false, message: "Cliente no hallado" });
        }

        // Buscamos el teléfono de soporte dinámico de la tabla empresa
        const [empresa] = await db.execute("SELECT TelSoporte FROM empresa WHERE TelSoporte != '' LIMIT 1");
        let telSoporte = empresa.length > 0 ? empresa[0].TelSoporte : '529631320318';

        res.json({
            success: true,
            cliente: rows[0],
            telefonoSoporte: telSoporte
        });
    } catch (e) {
        console.error("❌ Error en GET perfil:", e.message);
        res.status(500).json({ success: false, error: e.message });
    }
});

// --- 2. ACTUALIZAR DATOS DEL PERFIL (PUT) ---
app.put('/api/cliente/perfil', async (req, res) => {
    const { 
        id, nombreCompleto, email, direccion, colonia, cp, ciudad, estado 
    } = req.body;

    console.log("💾 Guardando cambios para cliente ID:", id);

    try {
        const sql = `
            UPDATE clientes SET 
                Nombre2 = ?, 
                email = ?, 
                Calle = ?, 
                Barrio = ?, 
                Cp = ?, 
                Ciudad = ?, 
                Estado = ? 
            WHERE Id = ?
        `;

        await db.execute(sql, [
            nombreCompleto ? nombreCompleto.toUpperCase() : '',
            email || '',
            direccion ? direccion.toUpperCase() : '',
            colonia ? colonia.toUpperCase() : '',
            cp || '',
            ciudad ? ciudad.toUpperCase() : '',
            estado ? estado.toUpperCase() : '',
            id
        ]);

        res.json({ success: true, message: "¡Perfil actualizado con éxito!" });
    } catch (e) {
        console.error("❌ Error en UPDATE perfil:", e.message);
        res.status(500).json({ success: false, error: e.message });
    }
});

// ==========================================
// LOGIN Y CATALOGOS
// ==========================================
app.post('/api/cliente/login', async (req, res) => {
console.log("Datos recibidos en el servidor:", req.body);
    const { telefono, password } = req.body; // Cambiamos email por telefono
    try {
        const [rows] = await db.execute(
    "SELECT Id, Nombre, Nombre2, email, Cel FROM clientes WHERE Cel = ? AND Password = ?",
    [telefono, password]
);

        if (rows.length > 0) {
            res.json({ success: true, cliente: rows[0] });
        } else {
            res.status(401).json({ success: false, message: "Teléfono o contraseña incorrectos" });
        }
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

// ==========================================
// SEGURIDAD PLUS: LOGIN ADMINISTRATIVO
// ==========================================
app.post('/api/login', async (req, res) => { 
    try {
        // Extraemos de forma segura
        const sqlPermisos = `
    -- Permisos del Rol
    SELECT p.slug, 1 as fuente FROM sec_permisos p
    INNER JOIN sec_rol_permisos rp ON p.id_permiso = rp.id_permiso
    WHERE rp.id_rol = ? AND p.activo = 1
    
    UNION
    
    -- Permisos específicos del Usuario (que sobrescriben al rol)
    SELECT p.slug, 2 as fuente FROM sec_permisos p
    INNER JOIN sec_usuario_permisos up ON p.id_permiso = up.id_permiso
    WHERE up.id_usuario = ? AND up.valor = 1
`;
        const userBody = req.body.username || req.body.user || req.body.nombre || "";
        const passBody = req.body.password || "";

        if (!userBody || !passBody) {
            return res.status(400).json({ success: false, message: 'Datos incompletos' });
        }

        const cleanUser = userBody.toString().trim();
        const cleanPass = passBody.toString().trim();

        // Consulta usando los nombres reales de tu tabla (Nombre)
        const sqlUser = `
            SELECT u.*, r.nombre_rol 
            FROM usuarios u
            LEFT JOIN sec_roles r ON u.id_rol = r.id_rol
            WHERE TRIM(u.Nombre) = ?`;

        const [users] = await db.execute(sqlUser, [cleanUser]);

        if (users.length === 0) {
            return res.status(401).json({ success: false, message: 'Usuario no encontrado' });
        }

        const user = users[0];
        let loginExitoso = false;

        // Verificación con bcrypt (usando la variable importada arriba)
        if (user.password_hash) {
            loginExitoso = await bcrypt.compare(cleanPass, user.password_hash);
        } 
        // Verificación Legacy (campo Password)
        else if (user.Password && user.Password.toString().trim() === cleanPass) {
            loginExitoso = true;
            // Migración automática a Hash
            const nuevoHash = await bcrypt.hash(cleanPass, 10);
            await db.execute('UPDATE usuarios SET password_hash = ? WHERE CveUsuario = ?', [nuevoHash, user.CveUsuario]);
        }

        if (loginExitoso) {
            const sqlPermisos = `
                SELECT p.slug 
                FROM sec_permisos p
                INNER JOIN sec_rol_permisos rp ON p.id_permiso = rp.id_permiso
                WHERE rp.id_rol = ? AND p.activo = 1`;
            
            const [permisos] = await db.execute(sqlPermisos, [user.id_rol]);
            const listaSlugs = permisos.map(p => p.slug);

            res.json({ 
                success: true, 
                user: user.Nombre, 
                rol: user.nombre_rol || user.Rol,
                permisos: listaSlugs 
            });
        } else {
            res.status(401).json({ success: false, message: 'Clave incorrecta' });
        }

    } catch (e) { 
        console.error("Error en login administrativo:", e); // Esto ahora saldrá bien en el log
        res.status(500).json({ success: false, message: "Error interno" }); 
    }
});

app.get('/api/tipos', async (req, res) => {
    try {
        const [rows] = await db.execute("SELECT Descripcion, Letra, Consecutivo FROM CATTIPOPROD ORDER BY Descripcion ASC");
        res.json(rows);
    } catch (e) { res.status(500).send(e.message); }
});

app.get('/api/siguiente-clave', async (req, res) => {
    try {
        const [rows] = await db.execute("SELECT MAX(CAST(Clave AS UNSIGNED)) + 1 as siguiente FROM PRODUCTOS");
        res.json({ siguiente: rows[0].siguiente || 1 });
    } catch (e) { res.status(500).send(e.message); }
});

app.get('/api/sucursales', async (req, res) => { 
    const soloApp = req.query.soloApp === 'true';
    try { 
        let sql = 'SELECT ID, sucursal, InfoEnvio, AppVisible, Pedidos FROM Empresa';
        if (soloApp) sql += ' WHERE AppVisible = 1';
        sql += ' ORDER BY ID';
        
        const [results] = await db.execute(sql); 
        res.json(results); 
    } catch (e) { 
        res.status(500).send(e.message); 
    }
});

// ==========================================
// REPORTES
// ==========================================

app.get('/api/reportes/cajas', async (req, res) => {
    try {
        const queryDetalle = `SELECT COALESCE(E.sucursal, CONCAT('SUC ', C.NumSuc)) AS NombreSucursal, C.NumSuc, C.NumCaja, C.Nombre AS NombreCajero, (C.Efectivo + C.Tarjeta + C.Cheque) as VentaTotal, C.Efectivo, C.Tarjeta, C.Cheque as Bancario, C.Devolucion as Devoluciones, C.Retiro as Retiros FROM catcaja C LEFT JOIN Empresa E ON CAST(C.NumSuc AS UNSIGNED) = CAST(E.ID AS UNSIGNED) ORDER BY CAST(C.NumSuc AS UNSIGNED) ASC, C.NumCaja ASC`;
        const [detalles] = await db.execute(queryDetalle);
        const [globalRes] = await db.execute(`SELECT SUM(Efectivo+Tarjeta+Cheque) as TotalVenta, SUM(Efectivo) as TotalEfectivo, SUM(Tarjeta) as TotalTarjeta, SUM(Cheque) as TotalBancario FROM catcaja`);
        res.json({ detalles, global: globalRes[0] });
    } catch (e) { res.status(500).json({ error: e.message }); }
});

app.get('/api/reportes/historico', async (req, res) => {
    const { rango, mes, anio, fecha } = req.query; 
    let filtro = "";
    try {
        if (rango === 'dia') filtro = `WHERE CAST(V.Fecha AS CHAR) LIKE '${fecha}%'`;
        else if (rango === 'semana') filtro = `WHERE YEARWEEK(V.Fecha, 1) = YEARWEEK('${fecha}', 1)`;
        else if (rango === 'mes') filtro = `WHERE MONTH(V.Fecha) = ${parseInt(mes)} AND YEAR(V.Fecha) = ${parseInt(anio)}`;

        const queryDetalle = `SELECT COALESCE(E.sucursal, CONCAT('SUC ', V.NumSuc)) AS NombreSucursal, V.NumSuc, V.NumCaja, SUM(COALESCE(V.Efectivo,0)) as Efectivo, SUM(COALESCE(V.Tarjeta,0)) as Tarjeta, SUM(COALESCE(V.Cheque,0)) as Bancario, SUM(COALESCE(V.Retiro,0)) as Retiros, SUM(COALESCE(V.Entregar,0)) as EfectivoNeto, SUM(COALESCE(V.Efectivo,0) + COALESCE(V.Tarjeta,0) + COALESCE(V.Cheque,0)) as VentaTotal FROM venta_diaria V LEFT JOIN Empresa E ON CAST(V.NumSuc AS UNSIGNED) = CAST(E.ID AS UNSIGNED) ${filtro} GROUP BY V.NumSuc, V.NumCaja ORDER BY CAST(V.NumSuc AS UNSIGNED) ASC, V.NumCaja ASC`;
        const [detalles] = await db.execute(queryDetalle);
        const [globalRes] = await db.execute(`SELECT SUM(COALESCE(Efectivo,0)) as TotalEfectivo, SUM(COALESCE(Tarjeta,0)) as TotalTarjeta, SUM(COALESCE(Cheque,0)) as TotalBancario, SUM(COALESCE(Entregar,0)) as TotalEfectivoNeto FROM venta_diaria V ${filtro}`);
        res.json({ detalles, global: globalRes[0] || {} });
    } catch (e) { res.status(500).json({ error: e.message }); }
});

app.get('/api/reportes/retiros-detalle', async (req, res) => {
    const { numSuc, numCaja, fechaInicio, fechaFin } = req.query;
    
    try {
        // Limpiamos las fechas para asegurar formato YYYY-MM-DD
        const fIni = fechaInicio.split(' ')[0];
        const fFin = fechaFin.split(' ')[0];

        console.log(`Buscando retiros en: Suc ${numSuc}, Caja ${numCaja}, Fechas: ${fIni} al ${fFin}`);

        // Usamos DATE(r.Fecha) para asegurar que la comparación sea solo por día
        const query = `
            SELECT 
                r.Motivo, 
                CAST(r.Monto AS DECIMAL(19,2)) as Monto, 
                COALESCE(u.Nombre, 'Vendedor ' + r.Vendedor) AS NombreVendedor, 
                r.Fecha 
            FROM retiros r 
            LEFT JOIN usuarios u ON CAST(r.Vendedor AS UNSIGNED) = CAST(u.CveUsuario AS UNSIGNED)
            WHERE CAST(r.NumSuc AS UNSIGNED) = ? 
              AND CAST(r.NumCaja AS UNSIGNED) = ? 
              AND DATE(r.Fecha) BETWEEN ? AND ?
            ORDER BY r.Id DESC`;

        const [results] = await db.execute(query, [
            parseInt(numSuc), 
            parseInt(numCaja), 
            fIni, 
            fFin
        ]);

        console.log(`Resultado: ${results.length} retiros encontrados.`);
        res.json(results);

    } catch (e) { 
        console.error("!!! ERROR CRÍTICO EN RETIROS:", e.message);
        res.status(500).json([]); 
    }
});

// OBTENER PRODUCTOS DEL CARRITO (Versión Corregida y Optimizada)
app.get('/api/carrito', async (req, res) => {
    const ip_add = req.query.ip_add || 'APP_USER';
    try {
        const [itemsCart] = await db.execute("SELECT num_suc FROM cart WHERE ip_add = ? LIMIT 1", [ip_add]);
        if (itemsCart.length === 0) return res.json([]);
        const sucId = itemsCart[0].num_suc;

        const sqlFinal = `
            SELECT c.*, p.Descripcion, p.drive_id, p.Foto, p.Clave, p.Precio1, p.Precio2, p.Precio3, p.Min1, p.Min2, p.Min3,
            a.ExisPVentas as stock_disponible,
            e.Sucursal as NombreSucursal,
            e.Pedidos as permite_pedidos,
            e.mincompra as minimo_sucursal
            FROM cart c
            JOIN productos p ON c.p_id = p.Id
            LEFT JOIN alm${sucId} a ON p.Clave = a.Clave
            LEFT JOIN Empresa e ON e.Id = c.num_suc
            WHERE c.ip_add = ?`;

        const [results] = await db.execute(sqlFinal, [ip_add]);
        res.json(results);
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

app.get('/api/carrito/contar', async (req, res) => {
    const ip_add = req.query.ip_add || 'APP_USER';
    try {
        const [rows] = await db.execute("SELECT SUM(qty) as total FROM cart WHERE ip_add = ?", [ip_add]);
        res.json({ total: rows[0].total || 0 });
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

// AGREGAR AL CARRITO (Asegúrate de que este bloque esté en server.js)
// BUSCA ESTA RUTA Y AJUSTA EL SQL:
app.post('/api/agregar_carrito', async (req, res) => {
    const { p_id, qty, p_price, ip_add, num_suc, is_increment } = req.body;
    const cantidadLimpia = parseInt(qty) || 1; 
    const user_ip = ip_add || 'APP_USER';
    const tablaAlm = `alm${num_suc}`;

    try {
        // ==========================================================
        // 1. EL "PORTERO": VALIDACIÓN DE SUCURSAL ÚNICA
        // ==========================================================
        // Buscamos si ya existe algún producto de otra sucursal
        const [existingCart] = await db.execute(
            "SELECT num_suc FROM cart WHERE ip_add = ? LIMIT 1", 
            [user_ip]
        );

        if (existingCart.length > 0) {
            const sucActualEnCarrito = existingCart[0].num_suc;
            
            // Si la sucursal del carrito es diferente a la que queremos agregar...
            if (parseInt(sucActualEnCarrito) !== parseInt(num_suc)) {
                return res.status(400).json({ 
                    success: false, 
                    error: "DIFERENTE_SUCURSAL",
                    message: "Tu carrito ya tiene productos de otro almacén." 
                });
            }
        }
        // ==========================================================

        // 2. Obtener Stock y Cantidad actual (Tu lógica original corregida)
        const [prodInfo] = await db.execute(
            `SELECT p.Clave, a.ExisPVentas FROM productos p 
             LEFT JOIN ${tablaAlm} a ON p.Clave = a.Clave WHERE p.Id = ?`, [p_id]
        );
        
        const [cartInfo] = await db.execute(
            "SELECT qty FROM cart WHERE p_id = ? AND ip_add = ?", [p_id, user_ip]
        );

        const stockDisponible = prodInfo[0]?.ExisPVentas || 0;
        const cantidadActual = cartInfo.length > 0 ? cartInfo[0].qty : 0;
        const stockLimpio = Math.floor(parseFloat(stockDisponible));
        
        let nuevaCantidadFinal = is_increment ? (cantidadActual + cantidadLimpia) : cantidadLimpia;

        // --- BLOQUEO DE SEGURIDAD PARA MÍNIMOS ---
        if (nuevaCantidadFinal < 1) {
            return res.status(400).json({
                success: false,
                error: "CANTIDAD_MINIMA",
                message: "La cantidad mínima permitida es 1 pieza."
            });
        }

        // --- VALIDACIÓN DE STOCK ---
        if (nuevaCantidadFinal > cantidadActual) {
            if (nuevaCantidadFinal > stockDisponible) {
                return res.status(400).json({ 
                    success: false, 
                    error: "SIN_STOCK", 
                    message: `Stock insuficiente. Máximo disponible: ${stockLimpio}` 
                });
            }
        }

        // 3. Guardar o Actualizar en MariaDB
        if (cartInfo.length > 0) {
            await db.execute(
                "UPDATE cart SET qty = ?, p_price = ?, num_suc = ? WHERE p_id = ? AND ip_add = ?",
                [nuevaCantidadFinal, p_price, num_suc, p_id, user_ip]
            );
        } else {
            await db.execute(
                "INSERT INTO cart (p_id, ip_add, qty, p_price, num_suc) VALUES (?, ?, ?, ?, ?)",
                [p_id, user_ip, nuevaCantidadFinal, p_price, num_suc]
            );
        }
        
        res.json({ success: true });

    } catch (e) {
        console.error("Error en agregar_carrito:", e.message);
        res.status(500).json({ error: e.message });
    }
});

// ELIMINAR DEL CARRITO
app.post('/api/carrito/eliminar', async (req, res) => {
    const { p_id, ip_add } = req.body;
    try {
        await db.execute("DELETE FROM cart WHERE p_id = ? AND ip_add = ?", [p_id, ip_add || 'APP_USER']);
        res.json({ success: true });
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

// En tu server.js o archivo de rutas
// Endpoint para Validar Stock Final antes de mostrar mensaje de compromiso
// VALIDAR STOCK FINAL: Ajustado a la estructura de tablas almX
app.post('/api/carrito/validar-stock-final', async (req, res) => {
    const { items, idSuc } = req.body;
    try {
        const detallesErrores = [];
        for (const item of items) {
            // Buscamos en la tabla alm correspondiente usando la Clave del producto
            const [stockData] = await db.execute(
                `SELECT a.ExisPVentas FROM alm${idSuc} a 
                 JOIN productos p ON a.Clave = p.Clave 
                 WHERE p.Id = ?`, [item.p_id]
            );

            const disponible = stockData[0]?.ExisPVentas || 0;
            if (disponible < item.qty) {
                detallesErrores.push({
                    nombre: item.Descripcion,
                    disponible: disponible,
                    solicitado: item.qty
                });
            }
        }
        if (detallesErrores.length > 0) return res.json({ status: 'error', detalles: detallesErrores });
        res.json({ status: 'ok' });
    } catch (e) {
        res.status(500).json({ status: 'error', mensaje: e.message });
    }
});

// Endpoint corregido para usar Promesas (async/await)
app.get('/api/mensajes/:slug', async (req, res) => {
    const { slug } = req.params;
    try {
        const [rows] = await db.execute("SELECT encabezado, descripcion FROM mensaje WHERE slug = ?", [slug]);
        if (rows.length > 0) {
            res.json(rows[0]); // Aquí decía results, debe ser rows
        } else {
            res.status(404).json({ encabezado: "Aviso", descripcion: "Mensaje no encontrado" });
        }
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});
// ==========================================
// GESTIÓN DE PRODUCTOS (ABMC)
// ==========================================

// ==========================================
// GESTIÓN DE PRODUCTOS (TIENDA Y INVENTARIO)
// ==========================================

app.get('/api/inventario', async (req, res) => {
    const qRaw = req.query.q || '';
    const page = parseInt(req.query.page) || 0; 
    const idSuc = req.query.idSuc || 1; 
    const seed = req.query.seed || 1; // Recibimos la semilla de la App
    const limit = 10; 
    const offset = page * limit;
    const q = `%${qRaw}%`;
    
    try {
        const camposSelect = `
            p.Id, p.Clave, p.Descripcion, p.product_desc, p.Precio1, p.Precio2, p.Precio3, 
            p.Min1, p.Min2, p.Min3, p.Foto, p.Tipo, p.status, p.Activo,
            CAST(a.ExisPVentas AS SIGNED) as stock_disponible
        `;

        let query;
        let params;

        if (qRaw === '') {
            // OPTIMIZACIÓN: RAND(seed) permite aleatoriedad constante durante la sesión
            query = `SELECT ${camposSelect}
                     FROM PRODUCTOS p
                     INNER JOIN alm${idSuc} a ON p.Clave = a.Clave
                     WHERE p.status = 1 AND a.ExisPVentas > 0
                     ORDER BY RAND(${seed}) 
                     LIMIT ? OFFSET ?`;
            params = [limit, offset];
        } else {
            // Limpiamos el texto para evitar que espacios extras arruinen el LIKE
            const searchPattern = `%${qRaw.trim()}%`;

            query = `SELECT ${camposSelect}
                     FROM PRODUCTOS p
                     INNER JOIN alm${idSuc} a ON p.Clave = a.Clave
                     WHERE p.status = 1 
                     AND a.ExisPVentas > 0
                     AND (
                        p.Descripcion LIKE ? 
                        OR p.Clave LIKE ? 
                        OR p.Tipo LIKE ?
                     )
                     ORDER BY 
                        (p.Descripcion LIKE ?) DESC, -- Los que EMPIEZAN con la palabra van primero
                        p.Descripcion ASC 
                     LIMIT ? OFFSET ?`;
            
            // Pasamos el patrón de búsqueda para los 3 campos + 1 para el orden de relevancia
            params = [searchPattern, searchPattern, searchPattern, `${qRaw.trim()}%`, limit, offset];
        }

        const [results] = await db.execute(query, params);
        res.json(results);
    } catch (e) { 
        console.error("Error en Inventario Aleatorio Optimizado:", e.message);
        res.status(500).json({ error: e.message }); 
    }
});


// --- RUTA ALTA PRODUCTO ---
app.post('/api/abmc/producto/nuevo', async (req, res) => {
    const b = req.body;
    console.log("-----------------------------------------");
    console.log("ALTA DE PRODUCTO: " + b.Clave + " (Tipo: " + b.Tipo + ")");
    
    let conn;
    try {
        conn = await db.getConnection();

        // 1. VERIFICAR SI LA CLAVE YA EXISTE
        const [existe] = await conn.execute('SELECT Clave FROM productos WHERE Clave = ?', [b.Clave]);
        
        if (existe.length > 0) {
            console.log(`!!! Intento de duplicado: La clave ${b.Clave} ya existe.`);
            return res.status(400).json({ 
                success: false, 
                error: `La clave "${b.Clave}" ya está registrada. Por favor, usa otra.` 
            });
        }

        await conn.beginTransaction(); 

        const costo = parseFloat(b.PCosto) || 0;

        // 2. Insertar en la tabla PRODUCTOS
        const sqlProducto = `INSERT INTO productos 
            (Clave, Descripcion, CB, ClavePro, PCosto, PCostoImp, PzasxCaja, Tipo, 
             Precio1, Precio2, Precio3, 
             FIngreso, Activo, status, IdGProd, IdIVA, Producto, PzasxPaq, Minimo, Maximo) 
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW(), 1, 1, 0, 2, 0, 1, 0, 0)`;
        
        const [result] = await conn.execute(sqlProducto, [
            b.Clave, 
            String(b.Descripcion).toUpperCase(), 
            b.CB || '',       
            b.ClavePro || '', 
            costo, 
            costo,            
            parseFloat(b.PzasxCaja) || 1, 
            b.Tipo,
            parseFloat(b.Precio1) || 0,
            parseFloat(b.Precio2) || 0,
            parseFloat(b.Precio3) || 0
        ]);

        if (result.affectedRows > 0) {
            // 3. Crear registros en los 5 almacenes (Inactivos = 0)
            for (let i = 1; i <= 5; i++) {
                await conn.execute(`INSERT INTO alm${i} (Clave, ExisPVentas, ExisBodega, ACTIVO) VALUES (?, 0, 0, 0)`, [b.Clave]);
            }

            // 4. INCREMENTAR EL CONSECUTIVO DEL TIPO DE PRODUCTO
            const sqlUpdateTipo = `UPDATE CATTIPOPROD SET Consecutivo = Consecutivo + 1 WHERE Descripcion = ?`;
            await conn.execute(sqlUpdateTipo, [b.Tipo]);

            // --- LÓGICA DE CÓDIGO DE BARRAS (Tabla config) ---
            // Obtenemos el folio sugerido actual antes de comparar
            const [configRows] = await conn.execute("SELECT CB FROM config LIMIT 1");
            
            if (configRows.length > 0) {
                const cbSugerido = configRows[0].CB.toString().trim();
                const cbRecibido = (b.CB || "").toString().trim();

                console.log(`Verificando CB - Recibido: [${cbRecibido}] | Sugerido en DB: [${cbSugerido}]`);

                // Solo incrementamos si el usuario usó el folio que el sistema sugirió
                if (cbRecibido === cbSugerido && cbRecibido !== "") {
                    await conn.execute("UPDATE config SET CB = CB + 1 LIMIT 1");
                    console.log(">>> ÉXITO: Se incrementó el folio CB en tabla config");
                } else {
                    console.log(">>> INFO: No se incrementó CB (Se usó uno manual o quedó vacío)");
                }
            }
            
            await conn.commit(); 
            
            // --- PEQUEÑA PAUSA PARA ASEGURAR ESCRITURA ---
            await new Promise(resolve => setTimeout(resolve, 200));

            // --- Recuperar el producto completo para devolverlo a Flutter ---
            const [rows] = await conn.execute('SELECT * FROM productos WHERE Clave = ?', [b.Clave]);
            
            console.log("ÉXITO TOTAL: Producto guardado y enviado a la App.");
            
            return res.status(200).json({ 
                success: true, 
                message: "Guardado completo y consecutivo incrementado",
                producto: rows[0],
                clave: b.Clave
            });
        } else {
            throw new Error("No se pudo insertar el producto");
        }

    } catch (err) {
        if (conn) await conn.rollback(); 
        console.error("!!! ERROR EN ALTA: " + err.message);
        return res.status(500).json({ success: false, error: err.message });
    } finally {
        if (conn) conn.release();
        console.log("-----------------------------------------");
    }
});

// NUEVA RUTA: Exclusiva para Administración (Muestra TODO)
// RUTA ADMIN: Trae existencias calculadas [Piezas + (Cajas * PzasxCaja)]
app.get('/api/admin/inventario', async (req, res) => {
    const qRaw = req.query.q || '';
    const page = parseInt(req.query.page) || 0; 
    const limit = 15; 
    const offset = page * limit;
    const q = `%${qRaw}%`;

    try {
        const query = `
            SELECT 
                p.Id, 
                TRIM(p.Clave) as Clave, 
                p.Descripcion, p.product_desc, p.PzasxCaja, p.Precio1, p.Precio2, p.Precio3, 
                p.Min1, p.Min2, p.Min3, p.Foto, p.status, p.Activo, p.Tipo, p.CB, p.ClavePro,
                
                -- Al ser 1 a 1, usamos COALESCE directamente. 
                -- Mantenemos el cálculo de piezas totales (ExisPVentas + Bodega * PzasxCaja)
                CAST(COALESCE(a1.ExisPVentas, 0) + (COALESCE(a1.ExisBodega, 0) * COALESCE(p.PzasxCaja, 1)) AS SIGNED) AS stock1,
                CAST(COALESCE(a2.ExisPVentas, 0) + (COALESCE(a2.ExisBodega, 0) * COALESCE(p.PzasxCaja, 1)) AS SIGNED) AS stock2,
                CAST(COALESCE(a3.ExisPVentas, 0) + (COALESCE(a3.ExisBodega, 0) * COALESCE(p.PzasxCaja, 1)) AS SIGNED) AS stock3,
                CAST(COALESCE(a4.ExisPVentas, 0) + (COALESCE(a4.ExisBodega, 0) * COALESCE(p.PzasxCaja, 1)) AS SIGNED) AS stock4,
                CAST(COALESCE(a5.ExisPVentas, 0) + (COALESCE(a5.ExisBodega, 0) * COALESCE(p.PzasxCaja, 1)) AS SIGNED) AS stock5
            FROM productos p
            LEFT JOIN alm1 a1 ON p.Clave = a1.Clave
            LEFT JOIN alm2 a2 ON p.Clave = a2.Clave
            LEFT JOIN alm3 a3 ON p.Clave = a3.Clave
            LEFT JOIN alm4 a4 ON p.Clave = a4.Clave
            LEFT JOIN alm5 a5 ON p.Clave = a5.Clave
            WHERE (
                p.Clave LIKE ? 
                OR p.Descripcion LIKE ? 
                OR p.CB LIKE ? 
                OR p.ClavePro LIKE ?
                -- El EXISTS es perfecto para la relación 1:N de codad porque no multiplica filas
                OR EXISTS (
                    SELECT 1 FROM codad ca 
                    WHERE ca.Clave = p.Clave 
                    AND ca.CB LIKE ?
                )
            )
            -- Agrupamos por Id para colapsar cualquier fila repetida accidental
            GROUP BY p.Id 
            -- Ordenamos por los más nuevos primero
            ORDER BY p.Id DESC 
            LIMIT ? OFFSET ?`;

        const [results] = await db.execute(query, [q, q, q, q, q, limit, offset]);
        res.json(results);
    } catch (e) { 
        console.error("Error en Inventario Admin (Optimización 1:1 y 1:N):", e.message);
        res.status(500).json({ error: e.message }); 
    }
});

app.post('/api/abmc/producto/:clave', async (req, res) => {
    const b = req.body; 
    const costo = parseFloat(b.PCosto) || 0; 
    
    // Aseguramos que los precios sean números antes de calcular utilidades
    const p1 = parseFloat(b.Precio1) || 0;
    const p2 = parseFloat(b.Precio2) || 0;
    const p3 = parseFloat(b.Precio3) || 0;

    // Calculamos utilidades
    const v = [
        calcularValores(p1, costo), 
        calcularValores(p2, costo), 
        calcularValores(p3, costo)
    ];

    let conn; 
    try { 
        conn = await db.getConnection(); 
        await conn.beginTransaction(); 
        
        // UPDATE con los nombres exactos de las columnas en tu MariaDB
        const sqlUpdate = `UPDATE productos SET 
            Descripcion=?, Presentacion=?, CB=?, ClavePro=?, PCosto=?, PCostoImp=?, PzasxCaja=?, Tipo=?, 
            Precio1=?, Precio2=?, Precio3=?, 
            Min1=?, Min2=?, Min3=?, 
            Util1=?, PorUtil1=?, Util2=?, PorUtil2=?, Util3=?, PorUtil3=?,
            Activo=?, status=?, pendiente=?, LotePend=?
            WHERE Clave=?`;

        await conn.execute(sqlUpdate, [ 
            (b.Descripcion || '').toUpperCase(), 
            b.Presentacion || '',              
            b.CB || req.params.clave, 
            b.ClavePro || '',         
            costo, 
            costo,                    
            parseFloat(b.PzasxCaja) || 1, 
            b.Tipo || '', 
            p1, 
            p2, 
            p3, 
            parseFloat(b.Min1) || 0, 
            parseFloat(b.Min2) || 0, 
            parseFloat(b.Min3) || 0, 
            v[0].utilidad, v[0].porutil, 
            v[1].utilidad, v[1].porutil, 
            v[2].utilidad, v[2].porutil, 
            b.Activo !== undefined ? b.Activo : 1,          // Activo
            b.Status !== undefined ? b.Status : 1,          // status (minúscula en DB)
            b.Pendiente !== undefined ? b.Pendiente : 0,    // pendiente (minúscula en DB)
            b.LotePend || null,                             // LotePend
            req.params.clave 
        ]); 

        // Actualización de stocks en almacenes
        if (b.stocks) { 
            for (let i = 1; i <= 5; i++) { 
                const s = b.stocks[`alm${i}`]; 
                if (s) {
                    await conn.execute(
                        `UPDATE alm${i} SET ExisPVentas=?, ExisBodega=?, ACTIVO=? WHERE Clave=?`, 
                        [
                            parseFloat(s.ExisPVentas) || 0, 
                            parseFloat(s.ExisBodega) || 0, 
                            (s.ACTIVO === 1 || s.ACTIVO === true) ? 1 : 0, 
                            req.params.clave
                        ]
                    );
                }
            } 
        } 
        
        await conn.commit(); 
        res.json({ success: true }); 
        
    } catch (e) { 
        if (conn) await conn.rollback(); 
        console.error("Error en Update de Producto:", e.message);
        res.status(500).json({ success: false, error: e.message }); 
    } finally { 
        if (conn) conn.release(); 
    }
});

app.get('/api/siguiente-cb', async (req, res) => {
    try {
        const [rows] = await db.execute("SELECT CB FROM Config LIMIT 1");
        res.json({ siguienteCB: rows[0]?.CB.toString() || "" });
    } catch (e) { res.status(500).send(e.message); }
});


// ==========================================
// FLUJO DE REGISTRO SEGURO (CON FIREBASE OTP)
// ==========================================

// 1. Verificar si el número ya existe y su estado
// 1. Verificar si el número ya existe y retornar sus datos para auto-llenado
app.post('/api/cliente/verificar-numero', async (req, res) => {
    let { telefono } = req.body;
    
    if (!telefono) {
        return res.status(400).json({ success: false, message: "El teléfono es requerido." });
    }

    try {
        // Limpiamos el teléfono por si llega con basura
        telefono = telefono.toString().replace(/\D/g, '');

        // Pedimos todos los campos necesarios para la App
        const query = `
            SELECT Id, Password, Nombre2, email, Calle, Barrio, CP, Ciudad, Estado 
            FROM clientes 
            WHERE Cel = ?`;
            
        const [rows] = await db.execute(query, [telefono]);
        
        if (rows.length > 0) {
            const cliente = rows[0];
            
            // Validamos si tiene contraseña (tu lógica original)
            const tienePass = cliente.Password && cliente.Password.toString().trim() !== '';
            
            // Enviamos la respuesta COMPLETA
            res.json({ 
                success: true, 
                existe: true, 
                tienePassword: tienePass,
                mensaje: tienePass 
                    ? "Este número ya está registrado. Por favor, inicia sesión." 
                    : "Este número ya es cliente de sucursal. Necesita crear una contraseña para la App.",
                // Enviamos los datos para que Flutter rellene los campos
                datos: {
                    nombre: cliente.Nombre2 || '',
                    email: cliente.email || '',
                    calle: cliente.Calle || '',
                    barrio: cliente.Barrio || '',
                    cp: cliente.CP || '',
                    ciudad: cliente.Ciudad || '',
                    estado: cliente.Estado || ''
                }
            });
        } else {
            // El número no existe en la base de datos
            res.json({ 
                success: true, 
                existe: false, 
                tienePassword: false, 
                mensaje: "Número disponible para registro." 
            });
        }
    } catch (e) {
        console.error("Error al verificar número:", e.message);
        res.status(500).json({ 
            success: false, 
            error: "Error en el servidor", 
            detalle: e.message 
        });
    }
});

// 2. Crear contraseña para cliente físico antiguo
app.post('/api/cliente/crear-password', async (req, res) => {
    const { telefono, password } = req.body;

    if (!telefono || !password) {
        return res.status(400).json({ success: false, message: "Teléfono y contraseña requeridos." });
    }

    try {
        const [result] = await db.execute(
            "UPDATE clientes SET Password = ? WHERE Cel = ? AND (Password IS NULL OR Password = '')", 
            [password, telefono]
        );

        if (result.affectedRows > 0) {
            res.json({ success: true, message: "Contraseña creada con éxito. Ya puedes iniciar sesión." });
        } else {
            res.status(400).json({ success: false, message: "No se pudo actualizar la contraseña." });
        }
    } catch (e) {
        console.error("Error al crear contraseña:", e.message);
        res.status(500).json({ success: false, error: e.message });
    }
});

// 3. Restablecer contraseña (Olvidé mi contraseña)
app.post('/api/cliente/reset-password', async (req, res) => {
    const { telefono, nuevaPassword } = req.body;

    if (!telefono || !nuevaPassword) {
        return res.status(400).json({ success: false, message: "Teléfono y nueva contraseña requeridos." });
    }

    try {
        const [result] = await db.execute(
            "UPDATE clientes SET Password = ? WHERE Cel = ?", 
            [nuevaPassword, telefono]
        );

        if (result.affectedRows > 0) {
            res.json({ success: true, message: "Contraseña actualizada correctamente. Ya puedes iniciar sesión." });
        } else {
            res.status(400).json({ success: false, message: "No se pudo actualizar. El número no existe." });
        }
    } catch (e) {
        console.error("Error al restablecer contraseña:", e.message);
        res.status(500).json({ success: false, error: e.message });
    }
});

// ==========================================
// REGISTRO CON FUSIÓN Y DOBLE VALIDACIÓN
// ==========================================
app.post('/api/cliente/registrar', async (req, res) => {
    let { 
        nombreCompleto = '', email = '', password = '', telefono = '', 
        direccion = '', colonia = '', cp = '', ciudad = '', estado = '',
        ultimosCuatroAnterior = '' 
    } = req.body;

    try {
        const telNuevo = telefono.toString().replace(/\D/g, '');
        const nombreBusqueda = nombreCompleto.trim().toUpperCase();
        const cpBusqueda = cp.toString().trim();

        // --- NUEVO: OBTENER EL TELÉFONO DE SOPORTE DINÁMICO ---
        let telSoporte = '529631320318'; // Número de respaldo por si acaso
        
        try {
            // Buscamos el primer registro donde TelSoporte NO sea nulo ni esté vacío
            const [empresaDB] = await db.execute(
                "SELECT TelSoporte FROM empresa WHERE TelSoporte IS NOT NULL AND TelSoporte != '' LIMIT 1"
            );

            if (empresaDB.length > 0) {
                telSoporte = empresaDB[0].TelSoporte.toString().replace(/\D/g, '');
                console.log("SOPORTE ENCONTRADO EN DB:", telSoporte); // <--- ESTO SALDRÁ EN PM2
            } else {
                console.log("OJO: No se encontró ningún TelSoporte válido en la tabla empresa.");
            }
        } catch (err) {
            console.error("Error consultando tabla empresa:", err.message);
        }   

        // Asegurar el prefijo 52
        if (telSoporte && !telSoporte.startsWith('52')) {
            telSoporte = '52' + telSoporte;
        }
        // ------------------------------------------------------

        // 1. ¿El teléfono nuevo ya existe?
        const [existeCel] = await db.execute("SELECT Id FROM clientes WHERE Cel = ?", [telNuevo]);
        if (existeCel.length > 0) {
            return res.status(400).json({ success: false, message: "Este número ya está registrado." });
        }

        // 2. Buscar por Nombre para Fusión
        const [registroViejo] = await db.execute(
            "SELECT Id, Cel, CP, Password FROM clientes WHERE UPPER(TRIM(Nombre2)) = ?", 
            [nombreBusqueda]
        );

        if (registroViejo.length > 0) {
            const clienteDB = registroViejo[0];
            const celEnDB = (clienteDB.Cel || '').toString().replace(/\D/g, '');

            // REGLA 1: Si ya tiene contraseña, bloqueo total por seguridad
            if (clienteDB.Password && clienteDB.Password.toString().trim() !== '') {
                return res.status(401).json({ 
                    success: false, 
                    error: "SEGURIDAD_BLOQUEO",
                    telefonoSoporte: telSoporte, // <--- ENVIAMOS EL TELÉFONO A FLUTTER
                    message: "Esta cuenta tiene una contraseña ya registrada. Por seguridad deberás contactar a nuestro soporte por WhatsApp." 
                });
            }

            // REGLA 2: Si el teléfono es diferente, pedimos validación
            if (celEnDB !== '' && celEnDB !== telNuevo) {
                console.log("Detectado conflicto de nombre. Enviando requiereValidacion a la App.");
                
                // Si la App aún no manda los 4 dígitos, mandamos la señal para que aparezca el cuadro azul
                if (!ultimosCuatroAnterior) {
                    return res.json({ 
                        success: false, 
                        requiereValidacion: true, // <--- DISPARADOR PARA FLUTTER
                        message: "Identificamos que ya eres cliente. Por seguridad, ingresa los últimos 4 dígitos de tu teléfono anterior." 
                    });
                }
                
                // Si ya los mandó, validamos CP y dígitos
                const cuatroDigitosDB = celEnDB.substring(celEnDB.length - 4);
                const cpDB = (clienteDB.CP || '').toString().trim();

                // --- LA NUEVA LÓGICA INTELIGENTE ---
                // Si la DB no tiene CP, lo damos por bueno (true). Si sí tiene, los comparamos.
                const cpCoincide = (cpDB === '') ? true : (cpDB === cpBusqueda);
                const cuatroCoinciden = cuatroDigitosDB === ultimosCuatroAnterior.toString().trim();

                if (!cpCoincide || !cuatroCoinciden) {
                    return res.status(401).json({ 
                        success: false, 
                        error: "VALIDACION_FALLIDA",
                        telefonoSoporte: telSoporte, // <--- ENVIAMOS EL TELÉFONO A FLUTTER
                        message: "Los datos de validación no coinciden con nuestros registros." 
                    });
                }
            }

            // FUSIONAR (Si todo está bien o no tenía teléfono previo)
            const sqlUpdate = `UPDATE clientes SET Cel=?, Password=?, email=?, Calle=?, Barrio=?, CP=?, Ciudad=?, Estado=? WHERE Id=?`;
            await db.execute(sqlUpdate, [telNuevo, password, email, direccion.toUpperCase(), colonia.toUpperCase(), cpBusqueda, ciudad.toUpperCase(), estado.toUpperCase(), clienteDB.Id]);
            return res.json({ success: true, message: "¡Cuenta vinculada con éxito!" });
        }

        // 3. Registro Nuevo (Si no hay coincidencia de nombre)
        const claveNombre = telNuevo.length >= 5 ? telNuevo.substring(telNuevo.length - 5) : telNuevo;
        const sqlInsert = `INSERT INTO clientes (Nombre, Nombre2, email, Password, Calle, Barrio, CP, Ciudad, Estado, Cel, Saldo, LimiteCred, AutCred, Dias) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 0, 0, 0)`;
        await db.execute(sqlInsert, [claveNombre, nombreBusqueda, email, password, direccion.toUpperCase(), colonia.toUpperCase(), cpBusqueda, ciudad.toUpperCase(), estado.toUpperCase(), telNuevo]);
        res.json({ success: true, message: "Registro creado exitosamente." });

    } catch (e) {
        res.status(500).json({ success: false, error: e.message });
    }
});

// Listar roles para el dropdown en la App
app.get('/api/roles', async (req, res) => {
    try {
        // Ahora ordenamos por el nivel jerárquico que acabamos de crear
        const [rows] = await db.execute("SELECT id_rol, nombre_rol, nivel FROM sec_roles WHERE activo = 1 ORDER BY nivel ASC");
        res.json(rows);
    } catch (e) { res.status(500).json({ error: e.message }); }
});


// Atajo rápido: Cambio de contraseña personal
app.post('/api/usuarios/cambiar-pass', async (req, res) => {
    const { nombre, nueva_pass } = req.body;
    try {
        const hash = await bcrypt.hash(nueva_pass.trim(), 10);
        await db.execute("UPDATE usuarios SET password_hash = ?, password = ? WHERE nombre = ?", [hash, nueva_pass, nombre]);
        res.json({ success: true });
    } catch (e) { res.status(500).json({ error: e.message }); }
});

app.get('/api/usuarios/lista', async (req, res) => {
    try {
        const [rows] = await db.execute(`
            SELECT 
                u.CveUsuario, u.Nombre, u.NombreLargo, u.NumSuc, 
                r.nombre_rol, r.nivel 
            FROM usuarios u 
            LEFT JOIN sec_roles r ON u.id_rol = r.id_rol 
            ORDER BY r.nivel ASC, u.Nombre ASC`); // <--- Ordena por rango y luego por nombre
        res.json(rows);
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

app.post('/api/usuarios/guardar', async (req, res) => {
    console.log("-----------------------------------------");
    console.log("PETICIÓN DE GUARDADO RECIBIDA");
    console.log("BODY:", req.body);

    const { id, nombre, nombreLargo, password, id_rol, num_suc, nombre_rol } = req.body;
    
    try {
        // Determinamos la sucursal: Superusuarios siempre van a la 0 (Global)
        const sucursalFinal = (nombre_rol === 'Superusuario') ? 0 : num_suc;
        
        // --- BLOQUE DE SEGURIDAD PARA EDICIÓN ---
        if (id) {
            // 1. Obtenemos el rol que tiene actualmente en la DB antes de actualizar
            const [rowsActual] = await db.execute(`
                SELECT r.nombre_rol 
                FROM usuarios u 
                JOIN sec_roles r ON u.id_rol = r.id_rol 
                WHERE u.CveUsuario = ?`, [id]);

            if (rowsActual.length > 0) {
                const rolActual = rowsActual[0].nombre_rol;

                // 2. Si es Superusuario y estás intentando cambiarle el rol a otra cosa...
                if (rolActual === 'Superusuario' && nombre_rol !== 'Superusuario') {
                    
                    // 3. Contamos cuántos quedan en total
                    const [superCount] = await db.execute(`
                        SELECT COUNT(*) as total 
                        FROM usuarios u 
                        JOIN sec_roles r ON u.id_rol = r.id_rol 
                        WHERE r.nombre_rol = 'Superusuario'`);

                    if (superCount[0].total <= 1) {
                        console.log("🚫 Intento de degradar al último Superusuario bloqueado.");
                        return res.status(403).json({ 
                            success: false, 
                            message: "BLOQUEO DE SEGURIDAD: No puedes cambiar el rol al único Superusuario del sistema." 
                        });
                    }
                }
            }

            // --- PROCEDER CON EL UPDATE ---
            let hash = password ? await bcrypt.hash(password.trim(), 10) : null;
            
            let sql = `UPDATE usuarios SET \`Nombre\` = ?, \`NombreLargo\` = ?, \`id_rol\` = ?, \`NumSuc\` = ? 
                      ${hash ? ', \`password_hash\` = ?, \`Password\` = ?' : ''} 
                      WHERE \`CveUsuario\` = ?`;
            
            let params = hash 
                ? [nombre, nombreLargo, id_rol, sucursalFinal, hash, password, id] 
                : [nombre, nombreLargo, id_rol, sucursalFinal, id];
                
            const [result] = await db.execute(sql, params);
            console.log("✅ Resultado UPDATE:", result);

        } else {
            // --- PROCEDER CON EL INSERT (USUARIO NUEVO) ---
            const hash = await bcrypt.hash(password.trim(), 10);
            const sql = `INSERT INTO usuarios (\`Nombre\`, \`NombreLargo\`, \`Password\`, \`password_hash\`, \`id_rol\`, \`NumSuc\`, \`FechaIni\`) 
                        VALUES (?, ?, ?, ?, ?, ?, NOW())`;
            
            await db.execute(sql, [nombre, nombreLargo, password, hash, id_rol, sucursalFinal]);
            console.log("✅ Usuario Nuevo Insertado");
        }

        res.json({ success: true });

    } catch (e) {
        console.error("❌ ERROR CRÍTICO EN GUARDADO:", e);
        res.status(500).json({ success: false, error: e.message });
    }
});

// Obtener todos los permisos y marcar cuáles tiene el usuario (por rol o por excepción)
app.get('/api/usuarios/:id/permisos', async (req, res) => {
    const { id } = req.params;
    console.log(`Buscando permisos para el usuario ID: ${id}`); // Ver esto en pm2 logs
    
    try {
        const sql = `
            SELECT 
                p.id_permiso, p.modulo, p.descripcion, p.slug,
                -- Verificamos si el usuario tiene el permiso por su ROL asignado
                IF(EXISTS(
                    SELECT 1 FROM sec_rol_permisos rp 
                    JOIN usuarios u ON rp.id_rol = u.id_rol 
                    WHERE u.CveUsuario = ? AND rp.id_permiso = p.id_permiso
                ), 1, 0) as tiene_por_rol,
                -- Verificamos si tiene una excepción manual (Personalizado)
                (SELECT valor FROM sec_usuario_permisos WHERE id_usuario = ? AND id_permiso = p.id_permiso) as valor_personalizado
            FROM sec_permisos p 
            WHERE p.activo = 1
            ORDER BY p.modulo ASC, p.descripcion ASC`;

        const [rows] = await db.execute(sql, [id, id]);
        console.log(`Se encontraron ${rows.length} permisos.`);
        res.json(rows);
    } catch (e) {
        console.error("ERROR EN GET PERMISOS:", e.message);
        res.status(500).json({ error: e.message });
    }
});

// Guardar o eliminar una excepción de permiso para un usuario
app.post('/api/usuarios/permisos/personalizar', async (req, res) => {
    const { id_usuario, id_permiso, valor } = req.body;
    try {
        // Borramos si ya existía una excepción previa
        await db.execute("DELETE FROM sec_usuario_permisos WHERE id_usuario = ? AND id_permiso = ?", [id_usuario, id_permiso]);
        
        // Insertamos la nueva excepción
        if (valor !== null) {
            await db.execute("INSERT INTO sec_usuario_permisos (id_usuario, id_permiso, valor) VALUES (?, ?, ?)", 
            [id_usuario, id_permiso, valor]);
        }
        res.json({ success: true });
    } catch (e) { res.status(500).json({ error: e.message }); }
});

// Obtener permisos de un Rol específico
app.get('/api/roles/:id/permisos', async (req, res) => {
    const { id } = req.params;
    console.log(`Buscando molde de permisos para el ROL ID: ${id}`);
    try {
        const sql = `
            SELECT 
                p.id_permiso, p.modulo, p.descripcion, p.slug,
                IF(EXISTS(SELECT 1 FROM sec_rol_permisos rp WHERE rp.id_rol = ? AND rp.id_permiso = p.id_permiso), 1, 0) as asignado
            FROM sec_permisos p 
            WHERE p.activo = 1
            ORDER BY p.modulo ASC, p.descripcion ASC`;
            
        const [rows] = await db.execute(sql, [id]);
        res.json(rows);
    } catch (e) {
        console.error("ERROR EN ROLES PERMISOS:", e.message);
        res.status(500).json({ error: e.message });
    }
});

// Asignar o quitar permiso a un Rol
app.post('/api/roles/permisos/update', async (req, res) => {
    const { id_rol, id_permiso, asignar } = req.body;
    try {
        if (asignar) {
            await db.execute("INSERT IGNORE INTO sec_rol_permisos (id_rol, id_permiso) VALUES (?, ?)", [id_rol, id_permiso]);
        } else {
            await db.execute("DELETE FROM sec_rol_permisos WHERE id_rol = ? AND id_permiso = ?", [id_rol, id_permiso]);
        }
        res.json({ success: true });
    } catch (e) { res.status(500).json({ error: e.message }); }
});

app.post('/api/usuarios/eliminar', async (req, res) => {
    const { id } = req.body;

    try {
        // 1. Buscamos info del usuario que queremos borrar
        const [userRows] = await db.execute(`
            SELECT u.Nombre, r.nombre_rol 
            FROM usuarios u 
            LEFT JOIN sec_roles r ON u.id_rol = r.id_rol 
            WHERE u.CveUsuario = ?`, [id]);

        if (userRows.length === 0) {
            return res.status(404).json({ success: false, message: "Usuario no encontrado." });
        }

        const usuarioABorrar = userRows[0];

        // 2. VALIDACIÓN: No se puede borrar un Superusuario directamente
        if (usuarioABorrar.nombre_rol === 'Superusuario') {
            
            // 3. VALIDACIÓN EXTRA: ¿Es el último Superusuario?
            const [superCount] = await db.execute(`
                SELECT COUNT(*) as total FROM usuarios u 
                JOIN sec_roles r ON u.id_rol = r.id_rol 
                WHERE r.nombre_rol = 'Superusuario'`);

            if (superCount[0].total <= 1) {
                return res.status(403).json({ 
                    success: false, 
                    message: "ERROR CRÍTICO: No puedes eliminar al único Superusuario del sistema." 
                });
            }

            return res.status(403).json({ 
                success: false, 
                message: "Protección de Rango: No puedes eliminar a un Superusuario. Primero cámbiale el rol a uno inferior." 
            });
        }

        // 4. Si pasó las pruebas, procedemos al borrado limpio
        await db.execute("DELETE FROM sec_usuario_permisos WHERE id_usuario = ?", [id]);
        await db.execute("DELETE FROM usuarios WHERE CveUsuario = ?", [id]);

        res.json({ success: true, message: "Usuario eliminado con éxito." });

    } catch (e) {
        console.error("ERROR AL ELIMINAR:", e);
        res.status(500).json({ success: false, error: e.message });
    }
});

app.post('/api/pedidos/nuevo', async (req, res) => {
    console.log("---------------");
    console.log("📥 ¡PETICIÓN DE PEDIDO RECIBIDA!");
    console.log("Datos:", req.body);
    console.log("---------------");
    // 1. Recibimos los datos que manda Flutter
    const { cliente_id, total, items, sucursal_id } = req.body;
    
    // Generamos folio aleatorio
    const invoice_no = Math.floor(Math.random() * 900000000) + 100000000;
    
    // Calculamos total piezas
    const totalQty = items.reduce((sum, item) => sum + parseInt(item.qty), 0);

    const connection = await db.getConnection();
    await connection.beginTransaction();

    try {
        // --- A. INSERTAR EN CABECERA ---
        const sqlCabecera = `
            INSERT INTO customer_orders 
            (customer_id, due_amount, invoice_no, qty, order_date, order_status) 
            VALUES (?, ?, ?, ?, NOW(), 'PENDIENTE')
        `;
        
        await connection.execute(sqlCabecera, [
            cliente_id, 
            total, 
            invoice_no, 
            totalQty
        ]);

        // --- B. INSERTAR DETALLES ---
        for (const item of items) {
            // Nota: Aquí validamos que venga item.num_suc, si no, usamos el general
            const itemSucursal = item.num_suc || sucursal_id || 1;

            const sqlDetalle = `
                INSERT INTO pending_orders 
                (customer_id, invoice_no, product_id, qty, order_status, p_price, num_suc, order_date) 
                VALUES (?, ?, ?, ?, 'PENDIENTE', ?, ?, NOW())
            `;
            // Agregué order_date al insert del detalle también por si acaso
            
            await connection.execute(sqlDetalle, [
                cliente_id,
                invoice_no,
                item.p_id,       // <--- OJO: Flutter debe mandar 'p_id' (Clave)
                item.qty,
                item.p_price,
                itemSucursal
            ]);
        }

        // --- C. OBTENER WHATSAPP (¡LO NUEVO!) ---
        // Consultamos el teléfono de la sucursal para devolverlo a la App
        const [sucursalRows] = await connection.execute(
            'SELECT TelefonoWhatsapp, Sucursal FROM empresa WHERE Id = ?', 
            [sucursal_id]
        );
        
        let whatsappDestino = '';
        let nombreSucursal = '';

        if (sucursalRows.length > 0) {
            whatsappDestino = sucursalRows[0].TelefonoWhatsapp;
            nombreSucursal = sucursalRows[0].Sucursal;
        }

        await connection.commit();

        console.log(`✅ Pedido #${invoice_no} guardado. Sucursal: ${nombreSucursal}`);
        
        // --- D. RESPONDER A FLUTTER ---
        res.json({ 
            success: true, 
            id_pedido: invoice_no,
            whatsapp: whatsappDestino, // <--- Enviamos el dato a la App
            sucursal: nombreSucursal
        });

    } catch (e) {
        await connection.rollback();
        console.error("❌ Error al guardar pedido:", e);
        res.status(500).json({ success: false, message: "Error al procesar el pedido." });
    } finally {
        connection.release();
    }
});

// OBTENER HISTORIAL (Versión DEFINITIVA y OPTIMIZADA)
app.get('/api/historial/:clienteId', async (req, res) => {
    const { clienteId } = req.params;

    try {
        // Consulta directa a la tabla de encabezados
        // Súper rápida gracias al índice idx_mov_cliente
        const query = `
            SELECT 
                Id AS ticket_id,
                Folio AS folio_ticket,
                DATE_FORMAT(Fecha, '%Y-%m-%d') as fecha,
                Hora as hora,
                Total AS total_pagado,
                pedidoweb AS referencia_web,
                CASE 
                    WHEN Tarjeta > 0 THEN 'Tarjeta'
                    WHEN Cheque > 0 THEN 'Cheque'
                    WHEN Credito > 0 THEN 'Crédito'
                    ELSE 'Efectivo'
                END AS metodo_pago,
                Estatus -- Si agregaste campo de estatus, o asumimos 'Entregado'
            FROM movimientos
            WHERE NoCliente = ?
            ORDER BY Fecha DESC, Hora DESC
            LIMIT 50
        `;

        const [historial] = await db.execute(query, [clienteId]);
        
        res.json({ success: true, data: historial });

    } catch (error) {
        console.error("Error historial:", error);
        res.status(500).json({ success: false, message: 'Error al obtener historial' });
    }
});

// ==========================================
// MÓDULO DE LANZAMIENTOS (LOTES PENDIENTES)
// ==========================================

// 1. Obtener resumen de Lotes (Fechas programadas)
app.get('/api/abmc/lotes-resumen', async (req, res) => {
    try {
        // Agrupamos por fecha y contamos cuántos están pendientes vs publicados
        const query = `
            SELECT 
                DATE_FORMAT(LotePend, '%Y-%m-%d') as FechaLote, 
                COUNT(*) as TotalProductos, 
                SUM(pendiente) as TotalPendientes,
                SUM(status) as TotalPublicados
            FROM productos
            WHERE LotePend IS NOT NULL
            GROUP BY DATE_FORMAT(LotePend, '%Y-%m-%d')
            ORDER BY FechaLote DESC
        `;
        const [rows] = await db.execute(query);
        res.json(rows);
    } catch (e) {
        console.error("Error al obtener resumen de lotes:", e);
        res.status(500).json({ error: e.message });
    }
});

// 2. Acción Masiva: Publicar o Revertir un Lote completo
app.post('/api/abmc/lotes/accion', async (req, res) => {
    const { fechaLote, accion } = req.body; // accion debe ser 'publicar' o 'revertir'
    
    try {
        // Lógica de negocio:
        // Si es 'publicar' -> status = 1 (visible), pendiente = 0
        // Si es 'revertir' -> status = 0 (invisible), pendiente = 1
        let statusVal = accion === 'publicar' ? 1 : 0;
        let pendienteVal = accion === 'publicar' ? 0 : 1;

        const query = `
            UPDATE productos 
            SET status = ?, pendiente = ? 
            WHERE DATE_FORMAT(LotePend, '%Y-%m-%d') = ?
        `;
        const [result] = await db.execute(query, [statusVal, pendienteVal, fechaLote]);
        
        res.json({ 
            success: true, 
            mensaje: `Lote ${accion === 'publicar' ? 'publicado' : 'revertido'} con éxito`,
            actualizados: result.affectedRows 
        });
    } catch (e) {
        console.error(`Error al ${accion} lote:`, e);
        res.status(500).json({ success: false, error: e.message });
    }
});

// 3. Obtener los productos detallados de un lote específico
app.get('/api/abmc/lotes/:fecha/productos', async (req, res) => {
    const { fecha } = req.params;
    try {
        const query = `
            SELECT 
                p.Id, p.Clave, p.Descripcion, p.Precio1, 
                p.Foto, p.status, p.Activo, p.pendiente, p.ClavePro,
                CAST(a1.ExisPVentas AS SIGNED) as stock_disponible
            FROM productos p
            LEFT JOIN alm1 a1 ON p.Clave = a1.Clave
            WHERE DATE_FORMAT(p.LotePend, '%Y-%m-%d') = ?
            ORDER BY p.Descripcion ASC
        `;
        const [rows] = await db.execute(query, [fecha]);
        res.json(rows);
    } catch (e) {
        console.error("Error al obtener productos del lote:", e);
        res.status(500).json({ error: e.message });
    }
});

// --- GET AVISO ACTIVO CON COLOR CONFIGURABLE ---
app.get('/api/avisos/activo', async (req, res) => {
    try {
        const sql = `
            SELECT mensaje, color_fondo 
            FROM avisos 
            WHERE activo = 1 
              AND (fecha_fin IS NULL OR fecha_fin > NOW())
              AND (fecha_inicio <= NOW())
            ORDER BY id DESC LIMIT 1
        `;
        const [rows] = await db.execute(sql);
        
        if (rows.length > 0) {
            res.json({ success: true, aviso: rows[0] });
        } else {
            res.json({ success: false });
        }
    } catch (e) {
        res.status(500).json({ success: false, error: e.message });
    }
});

// ==========================================
//   RUTAS ADMINISTRATIVAS PARA AVISOS
// ==========================================

// 1. OBTENER TODOS LOS AVISOS (Para la lista del Admin)
app.get('/api/admin/avisos', async (req, res) => {
    try {
        // Traemos todos, ordenados por el más reciente primero
        const sql = "SELECT * FROM avisos ORDER BY id DESC";
        const [rows] = await db.execute(sql);
        res.json({ success: true, avisos: rows });
    } catch (e) {
        console.error("❌ Error en GET admin avisos:", e.message);
        res.status(500).json({ success: false, error: e.message });
    }
});

// 2. CREAR UN NUEVO AVISO
app.post('/api/admin/avisos', async (req, res) => {
    const { mensaje, fecha_inicio, fecha_fin, color_fondo, activo } = req.body;
    console.log("🚀 Creando nuevo aviso:", mensaje);

    try {
        const sql = `
            INSERT INTO avisos (mensaje, fecha_inicio, fecha_fin, color_fondo, activo) 
            VALUES (?, ?, ?, ?, ?)
        `;
        await db.execute(sql, [
            mensaje, 
            fecha_inicio, 
            fecha_fin, 
            color_fondo || '#FFF176', 
            activo ? 1 : 0
        ]);
        res.json({ success: true, message: "¡Aviso creado con éxito!" });
    } catch (e) {
        console.error("❌ Error al crear aviso:", e.message);
        res.status(500).json({ success: false, error: e.message });
    }
});

// 3. ACTUALIZAR UN AVISO EXISTENTE (O cambiar su estado activo/inactivo)
app.put('/api/admin/avisos/:id', async (req, res) => {
    const { id } = req.params;
    const { mensaje, fecha_inicio, fecha_fin, color_fondo, activo } = req.body;

    try {
        // Primero verificamos qué datos llegaron para no borrar los que ya existen
        // Si solo llega 'activo', solo actualizamos ese campo (útil para el Switch de la lista)
        let sql, params;

        if (mensaje !== undefined) {
            // Actualización completa desde el Modal
            sql = `
                UPDATE avisos SET 
                    mensaje = ?, 
                    fecha_inicio = ?, 
                    fecha_fin = ?, 
                    color_fondo = ?, 
                    activo = ? 
                WHERE id = ?
            `;
            params = [mensaje, fecha_inicio, fecha_fin, color_fondo, activo, id];
        } else {
            // Actualización rápida del Switch (activo/inactivo)
            sql = "UPDATE avisos SET activo = ? WHERE id = ?";
            params = [activo, id];
        }

        const [result] = await db.execute(sql, params);

        if (result.affectedRows > 0) {
            res.json({ success: true, message: "Aviso actualizado correctamente" });
        } else {
            res.status(404).json({ success: false, message: "No se encontró el aviso" });
        }
    } catch (e) {
        console.error("❌ Error al actualizar aviso:", e.message);
        res.status(500).json({ success: false, error: e.message });
    }
});

app.listen(3000, '0.0.0.0', () => console.log('Servidor Factory operativo en puerto 3000'));