const express = require('express');
const mysql = require('mysql2/promise');
const cors = require('cors');
const path = require('path');
const multer = require('multer');
const fs = require('fs');

const app = express();
app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// --- CONFIGURACIÓN DE RUTAS Y DRIVE ---
const rutaFotos = path.join('C:', 'Users', 'Administrador', 'Mi unidad (factorymayoreo@gmail.com)', 'Fotos_CIF');

if (!fs.existsSync(rutaFotos)) {
    fs.mkdirSync(rutaFotos, { recursive: true });
}

app.use('/uploads', express.static(rutaFotos));

// --- CONFIGURACIÓN DE MULTER (ALMACENAMIENTO) ---
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

// --- CONFIGURACIÓN DE BASE DE DATOS ---
const db = mysql.createPool({
    host: '127.0.0.1',
    user: 'root',
    password: 'ADMIN', 
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
// RUTAS DE FOTOS
// ==========================================

app.post('/api/producto/upload-foto', upload.single('foto'), async (req, res) => {
    const { clave } = req.body;
    if (!req.file) return res.status(400).json({ success: false, message: 'No se subió ningún archivo' });
    try {
        const [rows] = await db.execute('SELECT Foto FROM PRODUCTOS WHERE Clave = ?', [clave]);
        if (rows.length > 0 && rows[0].Foto) {
            const viejaPath = path.join(rutaFotos, rows[0].Foto);
            if (fs.existsSync(viejaPath)) fs.unlinkSync(viejaPath);
        }
        const nuevoNombre = req.file.filename;
        await db.execute('UPDATE PRODUCTOS SET Foto = ? WHERE Clave = ?', [nuevoNombre, clave]);
        res.json({ success: true, foto: nuevoNombre });
    } catch (e) {
        res.status(500).json({ success: false, message: e.message });
    }
});

app.post('/api/producto/delete-foto', async (req, res) => {
    const { clave } = req.body;
    try {
        const [rows] = await db.execute('SELECT Foto FROM PRODUCTOS WHERE Clave = ?', [clave]);
        if (rows.length > 0 && rows[0].Foto) {
            const fotoPath = path.join(rutaFotos, rows[0].Foto);
            if (fs.existsSync(fotoPath)) fs.unlinkSync(fotoPath);
            await db.execute('UPDATE PRODUCTOS SET Foto = NULL WHERE Clave = ?', [clave]);
        }
        res.json({ success: true });
    } catch (e) {
        res.status(500).json({ success: false, message: e.message });
    }
});

// RUTA CRÍTICA: Obtener un solo producto para la pantalla de EDICIÓN
app.get('/api/producto/:clave', async (req, res) => {
    const { clave } = req.params;
    const query = `
        SELECT p.*, 
               a1.ExisPVentas AS alm1_pventas, a1.ExisBodega AS alm1_bodega, a1.ACTIVO AS alm1_activo,
               a2.ExisPVentas AS alm2_pventas, a2.ExisBodega AS alm2_bodega, a2.ACTIVO AS alm2_activo,
               a3.ExisPVentas AS alm3_pventas, a3.ExisBodega AS alm3_bodega, a3.ACTIVO AS alm3_activo,
               a4.ExisPVentas AS alm4_pventas, a4.ExisBodega AS alm4_bodega, a4.ACTIVO AS alm4_activo,
               a5.ExisPVentas AS alm5_pventas, a5.ExisBodega AS alm5_bodega, a5.ACTIVO AS alm5_activo 
        FROM productos p 
        LEFT JOIN alm1 a1 ON p.Clave = CONVERT(a1.Clave USING utf8mb3)
        LEFT JOIN alm2 a2 ON p.Clave = CONVERT(a2.Clave USING utf8mb3)
        LEFT JOIN alm3 a3 ON p.Clave = CONVERT(a3.Clave USING utf8mb3)
        LEFT JOIN alm4 a4 ON p.Clave = CONVERT(a4.Clave USING utf8mb3)
        LEFT JOIN alm5 a5 ON p.Clave = CONVERT(a5.Clave USING utf8mb3)
        WHERE p.Clave = ?`;
    try {
        const [results] = await db.execute(query, [clave]);
        res.json(results[0] || {}); // Enviamos el primer resultado o un objeto vacío
    } catch (e) {
        console.error("Error al obtener producto individual:", e.message);
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

app.post('/api/login', async (req, res) => { 
    const { username, password } = req.body;
    try {
        const [results] = await db.execute(`SELECT nombre, Rol FROM usuarios WHERE TRIM(nombre) = ? AND TRIM(password) = ?`, [username.trim(), password.trim()]);
        if (results.length > 0) res.json({ success: true, user: results[0].nombre, rol: results[0].Rol });
        else res.status(401).json({ success: false, message: 'Credenciales inválidas' });
    } catch (e) { res.status(500).json({ error: e.message }); }
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
    // Si viene el parámetro ?soloApp=true, filtramos. Si no, enviamos todo.
    const soloApp = req.query.soloApp === 'true';
    
    try { 
        let sql = 'SELECT ID, sucursal, InfoEnvio, AppVisible FROM Empresa';
        
        if (soloApp) {
            sql += ' WHERE AppVisible = 1';
        }
        
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

// OBTENER PRODUCTOS DEL CARRITO
app.get('/api/carrito', async (req, res) => {
    const ip_add = req.query.ip_add || 'APP_USER';
    
    // Esta consulta es más robusta: busca el stock en el almacén que indica el carrito
    const sql = `
        SELECT 
            c.p_id, c.qty, c.p_price, c.num_suc,
            p.Descripcion, p.Foto, p.Clave,
            p.Precio1, p.Precio2, p.Precio3, p.Min1, p.Min2, p.Min3,
            COALESCE(e.sucursal, 'Almacén') AS NombreSucursal,
            -- Buscamos el stock dinámicamente según la sucursal de cada item
            (SELECT ExisPVentas FROM 
                (SELECT 'alm1' as t UNION SELECT 'alm2' UNION SELECT 'alm3' UNION SELECT 'alm4' UNION SELECT 'alm5') as tabs 
                JOIN alm1 a1 ON c.num_suc = 1 AND p.Clave = a1.Clave
                OR c.num_suc = 2 AND p.Clave = (SELECT Clave FROM alm2 WHERE Clave = p.Clave)
                -- (Simplificado para mejor rendimiento abajo)
                LIMIT 1
            ) as stock_disponible
        FROM cart c 
        JOIN productos p ON c.p_id = p.Id 
        LEFT JOIN Empresa e ON c.num_suc = e.ID
        WHERE c.ip_add = ?`;

    // VERSION SIMPLIFICADA Y EFECTIVA:
    // Como usualmente un pedido es de una sola sucursal, usaremos el num_suc del primer item
    try {
        const [items] = await db.execute("SELECT num_suc FROM cart WHERE ip_add = ? LIMIT 1", [ip_add]);
        const sucId = items.length > 0 ? items[0].num_suc : 1;

        const sqlFinal = `
            SELECT c.*, p.Descripcion, p.Foto, p.Clave, p.Precio1, p.Precio2, p.Precio3, p.Min2, p.Min3,
            a.ExisPVentas as stock_disponible
            FROM cart c
            JOIN productos p ON c.p_id = p.Id
            LEFT JOIN alm${sucId} a ON p.Clave = a.Clave
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
    const user_ip = ip_add || 'APP_USER';
    const tablaAlm = `alm${num_suc}`;

    try {
        // 1. Obtener Stock y Cantidad actual en el carrito
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
        
        let nuevaCantidadFinal = is_increment ? (cantidadActual + parseInt(qty)) : parseInt(qty);

        // --- BLOQUEO DE SEGURIDAD PARA MÍNIMOS ---
        // Si la nueva cantidad es menor a 1, detenemos el proceso
        if (nuevaCantidadFinal < 1) {
            return res.status(400).json({
                success: false,
                error: "CANTIDAD_MINIMA",
                message: "La cantidad mínima permitida es 1 pieza."
            });
        }

        // --- VALIDACIÓN DE STOCK ---
        // Solo validamos stock si el usuario está aumentando la cantidad
        if (nuevaCantidadFinal > cantidadActual) {
            if (nuevaCantidadFinal > stockDisponible) {
                return res.status(400).json({ 
                    success: false, 
                    error: "SIN_STOCK", 
                    message: `Stock insuficiente. Máximo disponible: ${stockLimpio}` 
                });
            }
        }

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
    const limit = 10; 
    const offset = page * limit;
    const q = `%${qRaw.toLowerCase()}%`;
    
    try {
        let query;
        let params;

        const camposSelect = `
            p.Id, p.Clave, p.Descripcion, p.Precio1, p.Precio2, p.Precio3, 
            p.Min1, p.Min2, p.Min3, p.Foto, p.Tipo, p.status, p.Activo,
            CAST(COALESCE(a.ExisPVentas, 0) AS SIGNED) as stock_disponible
        `;

        if (qRaw === '') {
            // Filtramos por status = 1 Y por existencia > 0
            query = `SELECT ${camposSelect}
                     FROM PRODUCTOS p
                     LEFT JOIN alm${idSuc} a ON p.Clave = CONVERT(a.Clave USING utf8mb3)
                     WHERE p.status = 1 AND COALESCE(a.ExisPVentas, 0) > 0
                     ORDER BY RAND() 
                     LIMIT ? OFFSET ?`;
            params = [limit, offset];
        } else {
            // Filtramos por búsqueda, status = 1 Y por existencia > 0
            query = `SELECT ${camposSelect}
                     FROM PRODUCTOS p
                     LEFT JOIN alm${idSuc} a ON p.Clave = CONVERT(a.Clave USING utf8mb3)
                     WHERE (LOWER(p.Clave) LIKE ? OR LOWER(p.Descripcion) LIKE ? OR LOWER(p.Tipo) LIKE ?) 
                     AND p.status = 1 AND COALESCE(a.ExisPVentas, 0) > 0
                     ORDER BY p.Descripcion ASC 
                     LIMIT ? OFFSET ?`;
            params = [q, q, q, limit, offset];
        }

        const [results] = await db.execute(query, params);
        res.json(results);
    } catch (e) { 
        console.error("Error en Inventario Tienda:", e.message);
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
    const q = `%${qRaw.toLowerCase()}%`;

    try {
        const query = `
            SELECT 
                p.Id, 
                TRIM(p.Clave) as Clave, 
                p.Descripcion, p.PzasxCaja, p.Precio1, p.Precio2, p.Precio3, 
                p.Min1, p.Min2, p.Min3, p.Foto, p.status, p.Activo, p.Tipo, p.CB, p.ClavePro,
                
                CAST(COALESCE(MAX(a1.ExisPVentas), 0) + (COALESCE(MAX(a1.ExisBodega), 0) * COALESCE(p.PzasxCaja, 1)) AS SIGNED) AS stock1,
                CAST(COALESCE(MAX(a2.ExisPVentas), 0) + (COALESCE(MAX(a2.ExisBodega), 0) * COALESCE(p.PzasxCaja, 1)) AS SIGNED) AS stock2,
                CAST(COALESCE(MAX(a3.ExisPVentas), 0) + (COALESCE(MAX(a3.ExisBodega), 0) * COALESCE(p.PzasxCaja, 1)) AS SIGNED) AS stock3,
                CAST(COALESCE(MAX(a4.ExisPVentas), 0) + (COALESCE(MAX(a4.ExisBodega), 0) * COALESCE(p.PzasxCaja, 1)) AS SIGNED) AS stock4,
                CAST(COALESCE(MAX(a5.ExisPVentas), 0) + (COALESCE(MAX(a5.ExisBodega), 0) * COALESCE(p.PzasxCaja, 1)) AS SIGNED) AS stock5
            FROM productos p
            LEFT JOIN alm1 a1 ON p.Clave = CONVERT(a1.Clave USING utf8mb3)
            LEFT JOIN alm2 a2 ON p.Clave = CONVERT(a2.Clave USING utf8mb3)
            LEFT JOIN alm3 a3 ON p.Clave = CONVERT(a3.Clave USING utf8mb3)
            LEFT JOIN alm4 a4 ON p.Clave = CONVERT(a4.Clave USING utf8mb3)
            LEFT JOIN alm5 a5 ON p.Clave = CONVERT(a5.Clave USING utf8mb3)
            WHERE (
                LOWER(p.Clave) LIKE ? 
                OR LOWER(p.Descripcion) LIKE ? 
                OR LOWER(p.CB) LIKE ? 
                OR LOWER(p.ClavePro) LIKE ?
                -- BÚSQUEDA EN CÓDIGOS ADICIONALES
                OR EXISTS (
                    SELECT 1 FROM codad ca 
                    WHERE CONVERT(ca.Clave USING utf8mb3) = p.Clave 
                    AND LOWER(ca.CB) LIKE ?
                )
            )
            GROUP BY p.Id 
            ORDER BY p.Id DESC 
            LIMIT ? OFFSET ?`;

        // Pasamos 5 veces la variable 'q'
        const [results] = await db.execute(query, [q, q, q, q, q, limit, offset]);
        res.json(results);
    } catch (e) { 
        console.error("Error en Inventario Admin Completo:", e.message);
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

    // Mantenemos tus cálculos de valores originales
    const v = [
        calcularValores(p1, costo), 
        calcularValores(p2, costo), 
        calcularValores(p3, costo)
    ];

    let conn; 
    try { 
        conn = await db.getConnection(); 
        await conn.beginTransaction(); 
        
        // El SQL se mantiene igual, es correcto.
        const sqlUpdate = `UPDATE PRODUCTOS SET 
            Descripcion=?, CB=?, ClavePro=?, PCosto=?, PCostoImp=?, PzasxCaja=?, Tipo=?, 
            Precio1=?, Precio2=?, Precio3=?, 
            Min1=?, Min2=?, Min3=?, 
            Util1=?, PorUtil1=?, Util2=?, PorUtil2=?, Util3=?, PorUtil3=? 
            WHERE Clave=?`;

        await conn.execute(sqlUpdate, [ 
            (b.Descripcion || '').toUpperCase(), 
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
            req.params.clave 
        ]); 

        if (b.stocks) { 
            for (let i = 1; i <= 5; i++) { 
                const s = b.stocks[`alm${i}`]; 
                // Cambiamos el UPDATE de stock para ser más robustos con los valores recibidos
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
        console.error("Error en Update:", e.message);
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

app.post('/api/cliente/registrar', async (req, res) => {
    // Recibimos los datos desde Flutter
    const { 
        nombreCompleto = '', 
        email = '', 
        password = '', 
        telefono = '', 
        direccion = '', 
        colonia = '', 
        cp = '', 
        ciudad = '', 
        estado = '' 
    } = req.body;

    try {
        // 1. Validar que los datos mínimos existan (Email ya no es obligatorio aquí)
        if (!telefono || !password || !nombreCompleto) {
            return res.status(400).json({ 
                success: false, 
                message: "Faltan datos obligatorios (Nombre, Teléfono y Contraseña)" 
            });
        }

        // 2. Verificar si el teléfono ya existe para evitar duplicados
        const [existe] = await db.execute("SELECT Id FROM clientes WHERE Cel = ?", [telefono]);
        if (existe.length > 0) {
            return res.status(400).json({ 
                success: false, 
                message: "Este número de teléfono ya está registrado" 
            });
        }

        // 3. Lógica de la clave (últimos 5 dígitos del teléfono para la columna 'Nombre')
        const telefonoStr = telefono.toString().trim();
        const claveTelefono = telefonoStr.length >= 5 
            ? telefonoStr.substring(telefonoStr.length - 5) 
            : telefonoStr;

        // 4. SQL con tu nomenclatura específica
        const sql = `INSERT INTO clientes 
            (Nombre, Nombre2, email, Password, Calle, Barrio, CP, Ciudad, Estado, Cel, Saldo, LimiteCred, AutCred, Dias) 
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 0, 0, 0)`;
        
        const [result] = await db.execute(sql, [
            claveTelefono,      // Columna 'Nombre' (tu clave de 5 dígitos)
            nombreCompleto,     // Columna 'Nombre2'
            email || '',        // Si no hay email, enviamos cadena vacía
            password,
            direccion || '',    // Evitamos nulos si vienen vacíos
            colonia || '',
            cp || '',
            ciudad || '',
            estado || '',
            telefono            // Columna 'Cel'
        ]);

        res.json({ success: true, clienteId: result.insertId });

    } catch (e) {
        console.error("Error en registro:", e.message);
        res.status(500).json({ 
            success: false, 
            error: "Error interno al procesar el registro" 
        });
    }
});

app.listen(3000, '0.0.0.0', () => console.log('Servidor Factory operativo en puerto 3000'));