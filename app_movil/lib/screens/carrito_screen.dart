import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/tienda_service.dart';
import 'confirmacion_pedido_screen.dart';
import 'login_screen.dart';
import 'detalle_producto_screen.dart';
import '../widgets/tienda_modals.dart';

// IMPORTANTE: Asegúrate de importar aquí tu ficha de producto
// import 'ficha_producto_helper.dart';

class CarritoScreen extends StatefulWidget {
  final String baseUrl;
  const CarritoScreen({super.key, required this.baseUrl});

  @override
  State<CarritoScreen> createState() => _CarritoScreenState();
}

class _CarritoScreenState extends State<CarritoScreen> {
  Map<int, dynamic> erroresStock = {};
  List<dynamic> items = [];
  bool cargando = true;
  String nombreSucursal = "Cargando...";

  bool permitePedidos = true;
  double minCompra = 0;

  int _obtenerMultiplo(dynamic item) {
    int m1 = (double.tryParse(item['Min1']?.toString() ?? '0') ?? 0).toInt();
    // Si min1 es 0 o 1, el múltiplo es 1 (venta libre). Si es > 1, ese es el múltiplo.
    return m1 <= 1 ? 1 : m1;
  }

  double _calcularPrecioSegunEscala(dynamic item, int cantidad) {
    // Extraemos los precios y mínimos del item (vienen de tu JOIN en el ProLiant)
    double p1 = double.tryParse(item['Precio1']?.toString() ?? '0') ?? 0;
    double p2 = double.tryParse(item['Precio2']?.toString() ?? '0') ?? 0;
    double p3 = double.tryParse(item['Precio3']?.toString() ?? '0') ?? 0;

    int m2 = (double.tryParse(item['Min2']?.toString() ?? '0') ?? 0).toInt();
    int m3 = (double.tryParse(item['Min3']?.toString() ?? '0') ?? 0).toInt();

    // Lógica de escala: de mayor a menor
    if (p3 > 0 && m3 > 0 && cantidad >= m3) return p3;
    if (p2 > 0 && m2 > 0 && cantidad >= m2) return p2;
    return p1;
  }

  @override
  void initState() {
    super.initState();
    _obtenerCarrito();
  }

  // --- LÓGICA DE DATOS Y SERVIDOR ---

  Future<void> _obtenerCarrito() async {
    setState(() => cargando = true);
    try {
      final res = await http.get(
        Uri.parse('${widget.baseUrl}/api/carrito?ip_add=APP_USER'),
      );
      if (res.statusCode == 200) {
        setState(() {
          items = json.decode(res.body);
          if (items.isNotEmpty) {
            nombreSucursal =
                items[0]['NombreSucursal'] ?? "Sucursal Seleccionada";
            // --- NUEVA LÓGICA DE CAPTURA ---
            permitePedidos =
                (int.tryParse(items[0]['permite_pedidos']?.toString() ?? '1') ??
                    1) ==
                1;
            minCompra =
                double.tryParse(
                  items[0]['minimo_sucursal']?.toString() ?? '0',
                ) ??
                0;
            // ------------------------------
          }
        });
      }
    } catch (e) {
      debugPrint("Error obteniendo carrito: $e");
    } finally {
      setState(() => cargando = false);
    }
  }

  Future<void> _actualizarCantidad(dynamic item, int nuevaCantidad) async {
    if (nuevaCantidad < 1) return;
    try {
      final res = await http.post(
        Uri.parse('${widget.baseUrl}/api/agregar_carrito'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'p_id': item['p_id'],
          'qty': nuevaCantidad,
          'p_price': item['p_price'].toString(),
          'ip_add': 'APP_USER',
          'num_suc': item['num_suc'],
          'is_increment': false,
        }),
      );
      if (res.statusCode == 200) _obtenerCarrito();
    } catch (e) {
      debugPrint("Error: $e");
    }
  }

  Future<void> _eliminarItem(dynamic pId) async {
    final res = await http.post(
      Uri.parse('${widget.baseUrl}/api/carrito/eliminar'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'p_id': pId, 'ip_add': 'APP_USER'}),
    );
    if (res.statusCode == 200) {
      setState(() => erroresStock.remove(pId));
      _obtenerCarrito();
    }
  }

  double _calcularTotal() {
    double total = 0;
    for (var item in items) {
      total +=
          (double.tryParse(item['p_price'].toString()) ?? 0) *
          (int.tryParse(item['qty'].toString()) ?? 0);
    }
    return total;
  }

  // --- NUEVA LÓGICA DE VERIFICACIÓN (BOTÓN ROJO) ---

  void _verificarYContinuar() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String clienteId = prefs.getString('cliente_id') ?? "";

    if (clienteId.isEmpty) {
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => LoginScreen(baseUrl: widget.baseUrl),
        ),
      ).then((_) => _obtenerCarrito());
      return;
    }

    if (items.isEmpty) return;

    setState(() {
      cargando = true;
      erroresStock.clear();
    });

    int sucId = int.tryParse(items[0]['num_suc'].toString()) ?? 1;

    try {
      final respuesta = await TiendaService.validarStockFinal(
        widget.baseUrl,
        items,
        sucId,
      );

      setState(() => cargando = false);

      if (respuesta['status'] == 'ok') {
        // En lugar de ir directo a finalizar, vamos al RESUMEN
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ConfirmacionPedidoScreen(
              baseUrl: widget.baseUrl,
              items: items, // Pasamos la lista de productos
              total: _calcularTotal(), // Pasamos el total calculado
              // Aquí pasamos la función que realmente guarda en la DB
              onConfirmar: () {
                // Cerramos la pantalla de confirmación
                Navigator.pop(context);
                // Y ejecutamos el proceso final
                _finalizarPedido();
              },
            ),
          ),
        );
      } else {
        // --- AQUÍ ESTÁ EL ARREGLO ---
        setState(() {
          for (var error in respuesta['detalles']) {
            // Buscamos el item en nuestra lista local
            final item = items.firstWhere(
              (i) => i['Descripcion'] == error['nombre'],
            );

            // 1. Guardamos el error para que la tarjeta sepa que debe pintar
            erroresStock[item['p_id']] = error;

            // 2. ¡VITAL! Actualizamos el stock local con lo que dijo el servidor
            // Sin esta línea, la UI no sabe que qty > stock y no cambia de color
            item['stock_disponible'] = error['disponible'];
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Ajusta los productos en rojo o naranja"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      setState(() => cargando = false);
      debugPrint("Error verificación: $e");
    }
  }

  void _mostrarDialogoCantidadManual(dynamic item) {
    TextEditingController customQtyController = TextEditingController();
    int multiplo = _obtenerMultiplo(item);
    int stock =
        (double.tryParse(item['stock_disponible']?.toString() ?? '0') ?? 0)
            .toInt();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text("Cantidad personalizada"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (multiplo > 1)
              Text(
                "Este producto se vende en múltiplos de $multiplo",
                style: const TextStyle(
                  color: Colors.red,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            const SizedBox(height: 10),
            TextField(
              controller: customQtyController,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: InputDecoration(
                hintText: "Múltiplo sugerido: ${multiplo * 10}",
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CANCELAR"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD32F2F),
            ),
            onPressed: () {
              int? cant = int.tryParse(customQtyController.text);

              if (cant == null || cant <= 0) return;

              // VALIDACIÓN MATEMÁTICA DEL MÚLTIPLO
              if (cant % multiplo != 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      "❌ La cantidad debe ser múltiplo de $multiplo",
                    ),
                  ),
                );
                return;
              }

              if (cant > stock) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("❌ Stock insuficiente ($stock disponibles)"),
                  ),
                );
                return;
              }

              Navigator.pop(context);
              _procesarCambioCantidad(item, cant);
            },
            child: const Text("ACEPTAR", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _procesarCambioCantidad(dynamic item, int nuevaCantidad) async {
    // 1. Calculamos el nuevo precio basado en la escala
    double nuevoPrecio = _calcularPrecioSegunEscala(item, nuevaCantidad);

    // --- MEJORA ESTRUCTURAL: Respuesta instantánea ---
    setState(() {
      item['qty'] = nuevaCantidad; // Actualizamos cantidad localmente
      item['p_price'] = nuevoPrecio; // Actualizamos precio localmente
      erroresStock.remove(
        item['p_id'],
      ); // ¡Quitamos el color naranja de inmediato!
    });

    try {
      final res = await http.post(
        Uri.parse('${widget.baseUrl}/api/agregar_carrito'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'p_id': item['p_id'],
          'qty': nuevaCantidad,
          'p_price': nuevoPrecio.toString(),
          'ip_add': 'APP_USER',
          'num_suc': item['num_suc'],
          'is_increment': false,
        }),
      );
      // Solo refrescamos si hubo éxito, pero la UI ya se ve bien desde el setState de arriba
      //if (res.statusCode == 200) _obtenerCarrito();
    } catch (e) {
      debugPrint("Error actualizando cantidad: $e");
    }
  }

  void _confirmarVaciarCarrito() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text("¿Vaciar carrito?"),
        content: const Text(
          "Se eliminarán todos los productos de tu pedido actual.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CANCELAR", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD32F2F),
            ),
            onPressed: () async {
              Navigator.pop(context); // Cerramos el diálogo
              setState(() => cargando = true);

              try {
                // Llamamos al servicio para vaciar la tabla en MariaDB
                await TiendaService.vaciarCarrito(widget.baseUrl);

                if (mounted) {
                  setState(() {
                    items = [];
                    erroresStock.clear();
                    cargando = false;
                  });

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Carrito vaciado correctamente"),
                      backgroundColor: Colors.black87,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) setState(() => cargando = false);
                debugPrint("Error al vaciar: $e");
              }
            },
            child: const Text("VACIAR", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _abrirFichaDetalle(dynamic item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DetalleProductoScreen(
          item: item,
          baseUrl: widget.baseUrl,
          onAgregarTap: (itemParaAgregar) {
            // Si le pican a 'Agregar' desde el detalle,
            // sumamos 1 a la cantidad actual del carrito
            int currentQty = (int.tryParse(item['qty'].toString()) ?? 1);
            _actualizarCantidad(item, currentQty + 1);

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Cantidad actualizada en el carrito"),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _abrirSelectorConStockReal(dynamic item) async {
    try {
      // 1. Verificamos que tengamos los IDs necesarios
      final pId = item['p_id'];
      final nSuc = item['num_suc'];

      final response = await http.get(
        Uri.parse(
          '${widget.baseUrl}/api/producto/stock-actual?p_id=$pId&num_suc=$nSuc',
        ),
      );

      if (response.statusCode == 200) {
        final stockFresco = json.decode(response.body);

        // LOG DE SEGURIDAD: Revisa esto en tu terminal de VS Code
        debugPrint("Respuesta Servidor para ID $pId: $stockFresco");

        if (mounted) {
          setState(() {
            // 2. Inyectamos la "verdad" del servidor en el item
            item['stock_disponible'] = stockFresco['stock_disponible'];
            item['Min1'] = stockFresco['Min1'];

            // Aprovechamos para limpiar el error si el stock ahora es suficiente
            int qtyActual = (int.tryParse(item['qty'].toString()) ?? 0);
            int stockReal =
                (double.tryParse(stockFresco['stock_disponible'].toString()) ??
                        0)
                    .toInt();
            if (qtyActual <= stockReal) {
              erroresStock.remove(pId);
            }
          });

          // 3. Abrimos el modal pasando el objeto YA actualizado
          TiendaModals.mostrarSelectorCantidad(
            context: context,
            item: item,
            rojoFactory: const Color(0xFFD32F2F),
            formatCurrency: (val) =>
                "\$${double.tryParse(val.toString())?.toStringAsFixed(2) ?? '0.00'}",
            onAgregar: (qty, price) {
              _procesarCambioCantidad(item, int.parse(qty));
            },
          );
        }
      }
    } catch (e) {
      debugPrint("Error crítico de sincronización: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Error al conectar con el servidor HP ProLiant"),
        ),
      );
    }
  }

  Future<void> _finalizarPedido() async {
    // Aquí va tu lógica original de guardado en DB y envío de WhatsApp
    debugPrint("Procesando pedido final...");
    // ... resto de tu código de WhatsApp ...
  }

  // --- INTERFAZ (BUILD) ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text(
          "Mi Carrito",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFFD32F2F),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep, size: 28),
              onPressed: _confirmarVaciarCarrito,
              tooltip: "Vaciar carrito",
            ),
        ],
      ),
      body: SafeArea(
        bottom: true,
        top: false,
        child: cargando
            ? const Center(child: CircularProgressIndicator())
            : items.isEmpty
            ? const Center(child: Text("Tu carrito está vacío"))
            : Column(
                children: [
                  _CabeceraSucursal(nombre: nombreSucursal),
                  Expanded(
                    child: ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, index) => _TarjetaProducto(
                        item: items[index],
                        baseUrl: widget.baseUrl,
                        error: erroresStock[items[index]['p_id']],
                        onUpdate: _actualizarCantidad,
                        onDelete: _eliminarItem,
                        onShowFicha: _abrirFichaDetalle,
                        onSelectQty:
                            _abrirSelectorConStockReal, // <--- CAMBIA ESTO (Antes decía _mostrarSelectorCantidad)
                      ),
                    ),
                  ),
                  _ResumenCompra(
                    total: _calcularTotal(),
                    minCompra: minCompra, // <--- Agregar
                    permitePedidos: permitePedidos, // <--- Agregar
                    onPressed: _verificarYContinuar,
                  ),
                ],
              ),
      ),
    );
  }
}

// 1. Cabecera de Sucursal
class _CabeceraSucursal extends StatelessWidget {
  final String nombre;
  const _CabeceraSucursal({required this.nombre});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: Colors.amber[50],
      child: Row(
        children: [
          const Icon(Icons.store, color: Colors.orange, size: 20),
          const SizedBox(width: 10),
          Text(
            "Surtido desde: $nombre",
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// 2. La Tarjeta de cada Producto (Aquí está la lógica visual de errores)
class _TarjetaProducto extends StatelessWidget {
  final dynamic item;
  final String baseUrl;
  final dynamic error;
  final Function(dynamic, int) onUpdate;
  final Function(dynamic) onDelete;
  final Function(dynamic) onShowFicha;
  final Function(dynamic) onSelectQty;

  const _TarjetaProducto({
    required this.item,
    required this.baseUrl,
    this.error,
    required this.onUpdate,
    required this.onDelete,
    required this.onShowFicha,
    required this.onSelectQty,
  });

  @override
  Widget build(BuildContext context) {
    int qty = (double.tryParse(item['qty']?.toString() ?? '1') ?? 1).toInt();
    double precio = double.tryParse(item['p_price']?.toString() ?? '0') ?? 0;

    // Stock sin decimales y texto pulido
    int stockDisponible =
        (double.tryParse(item['stock_disponible']?.toString() ?? '0') ?? 0)
            .toInt();

    bool esAgotado = error != null && stockDisponible <= 0;
    // Error si la cantidad actual supera el stock reportado por el servidor
    bool mostrarError = error != null && qty > stockDisponible && !esAgotado;

    return Opacity(
      opacity: esAgotado
          ? 0.6
          : 1.0, // Un poco menos traslúcido para que sea legible
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        color: esAgotado
            ? Colors.red[50]
            : (mostrarError ? Colors.orange[50] : Colors.white),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: esAgotado
                ? Colors.red
                : (mostrarError ? Colors.orange : Colors.grey[200]!),
            width: 1.5,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Imagen del producto
              IgnorePointer(
                ignoring: esAgotado,
                child: GestureDetector(
                  onTap: () => onShowFicha(item),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      '$baseUrl/uploads/${item['Foto']}',
                      width: 75,
                      height: 75,
                      fit: BoxFit.cover,
                      errorBuilder: (c, e, s) =>
                          const Icon(Icons.image, size: 75),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Información del producto
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item['Descripcion'],
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: esAgotado ? Colors.grey[700] : Colors.black87,
                      ),
                    ),

                    // Mensaje de Advertencia (Naranja - Stock Insuficiente)
                    if (mostrarError)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          "Stock disponible: $stockDisponible",
                          style: const TextStyle(
                            color: Colors.orange,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),

                    // Mensaje Critico (Rojo - Agotado)
                    if (esAgotado)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          "PRODUCTO AGOTADO EN ESTE ALMACÉN",
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                      ),

                    const SizedBox(height: 10),

                    // Fila de Precios y Cantidad
                    Row(
                      children: [
                        Text(
                          "\$${precio.toStringAsFixed(2)}",
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Text(" x ", style: TextStyle(color: Colors.grey)),

                        // Selector de Cantidad
                        InkWell(
                          // Si está agotado, el botón no reacciona
                          onTap: esAgotado ? null : () => onSelectQty(item),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: esAgotado
                                    ? Colors.red[200]!
                                    : (mostrarError
                                          ? Colors.orange
                                          : Colors.grey[300]!),
                              ),
                              borderRadius: BorderRadius.circular(6),
                              color: esAgotado
                                  ? Colors.red[50]
                                  : (mostrarError
                                        ? Colors.orange[100]
                                        : Colors.grey[50]),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  "$qty",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: esAgotado
                                        ? Colors.red
                                        : Colors.black,
                                  ),
                                ),
                                // Solo mostramos la flecha si NO está agotado
                                if (!esAgotado)
                                  const Icon(Icons.arrow_drop_down, size: 18),
                              ],
                            ),
                          ),
                        ),
                        const Spacer(),

                        // Subtotal del Item
                        Text(
                          "\$${(precio * qty).toStringAsFixed(2)}",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: esAgotado
                                ? Colors.grey
                                : const Color(0xFFD32F2F),
                            // Si está agotado, tachamos el precio para indicar que no suma
                            decoration: esAgotado
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Botón eliminar
              IconButton(
                icon: const Icon(
                  Icons.delete_outline,
                  color: Colors.red,
                  size: 24,
                ),
                onPressed: () => onDelete(item['p_id']),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 3. Resumen Final de Compra (Total y Botón)
class _ResumenCompra extends StatelessWidget {
  final double total;
  final double minCompra;
  final bool permitePedidos;
  final VoidCallback onPressed;

  const _ResumenCompra({
    required this.total,
    required this.minCompra,
    required this.permitePedidos,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    String textoBoton = "VERIFICAR Y CONTINUAR";
    bool habilitado = true;
    Color colorBoton = const Color(0xFFD32F2F);

    if (!permitePedidos) {
      textoBoton = "Este almacén NO realiza envios";
      habilitado = false;
      colorBoton = Colors.grey;
    } else if (total < minCompra) {
      textoBoton = "El minimo de compra es: \$${minCompra.toStringAsFixed(0)}";
      habilitado = false;
      colorBoton = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "TOTAL ESTIMADO:",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                "\$${total.toStringAsFixed(2)}",
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFD32F2F),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: colorBoton,
                disabledBackgroundColor: Colors.grey[400],
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: habilitado ? onPressed : null,
              child: Text(
                textoBoton,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
