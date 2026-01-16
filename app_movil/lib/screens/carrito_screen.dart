import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/constants.dart';
import 'login_screen.dart';

class CarritoScreen extends StatefulWidget {
  final String baseUrl;
  const CarritoScreen({super.key, required this.baseUrl});

  @override
  State<CarritoScreen> createState() => _CarritoScreenState();
}

class _CarritoScreenState extends State<CarritoScreen> {
  List<dynamic> items = [];
  bool cargando = true;
  String nombreSucursal = "Cargando...";

  @override
  void initState() {
    super.initState();
    _obtenerCarrito();
  }

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
    // --- GUARDIA DE SEGURIDAD ---
    // Si el usuario intenta bajar de 1, no hacemos nada.
    if (nuevaCantidad < 1) {
      // Opcional: Podrías llamar a _eliminarItem(item['p_id'])
      // si quieres que al bajar de 1 se borre el producto.
      return;
    }

    int stock =
        (double.tryParse(item['stock_disponible']?.toString() ?? '0') ?? 0)
            .toInt();
    int cantidadActual = (double.tryParse(item['qty']?.toString() ?? '0') ?? 0)
        .toInt();

    if (nuevaCantidad > cantidadActual && nuevaCantidad > stock) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Límite alcanzado: $stock pz disponibles"),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

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
    if (res.statusCode == 200) _obtenerCarrito();
  }

  double _calcularTotal() {
    double total = 0;
    for (var item in items) {
      double precio = double.tryParse(item['p_price'].toString()) ?? 0;
      int cantidad = int.tryParse(item['qty'].toString()) ?? 0;
      total += (precio * cantidad);
    }
    return total;
  }

  Future<void> _verificarLoginYConfirmar() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? clienteId = prefs.getString('cliente_id');

    if (clienteId == null) {
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => LoginScreen(baseUrl: widget.baseUrl),
        ),
      );
      _obtenerCarrito();
    } else {
      _confirmarEnvioPedido();
    }
  }

  void _confirmarEnvioPedido() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text("¿Confirmar Pedido?"),
        content: const Text(
          "Se generará tu cotización y se enviará por WhatsApp.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("REVISAR"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () {
              Navigator.pop(context);
              _finalizarPedido();
            },
            child: const Text(
              "SÍ, ENVIAR",
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _finalizarPedido() async {
    setState(() => cargando = true);
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String clienteId = prefs.getString('cliente_id') ?? "0";
    String nombreCliente = prefs.getString('cliente_nombre') ?? "Cliente";

    // Obtenemos el ID de la sucursal del primer producto en el carrito
    int sucId = items.isNotEmpty
        ? int.parse(items[0]['num_suc'].toString())
        : 1;

    try {
      final res = await http.post(
        Uri.parse('${widget.baseUrl}/api/finalizar_pedido'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'ip_add': 'APP_USER',
          'customer_id': clienteId,
          'num_suc': sucId,
        }),
      );

      final data = json.decode(res.body);

      if (res.statusCode == 200) {
        String invoiceNo = data['invoice_no'].toString();

        // --- CAMBIO CLAVE: RECUPERAMOS EL TELÉFONO DINÁMICO ---
        // Si por alguna razón viene vacío, puedes poner uno de respaldo
        String telefonoDestino =
            data['whatsapp_phone']?.toString() ?? "521XXXXXXXXXX";

        String listaProductos = "";
        for (var i in items) {
          listaProductos += "• ${i['qty']} pz - ${i['Descripcion']}\n";
        }

        String mensaje =
            "📦 *NUEVO PEDIDO: #$invoiceNo*\n"
            "👤 *Cliente:* $nombreCliente\n"
            "🏢 *Almacén:* $nombreSucursal\n"
            "----------------------------------\n"
            "$listaProductos"
            "----------------------------------\n"
            "💰 *TOTAL:* ${formatCurrency(_calcularTotal())}";

        // USAMOS LA VARIABLE DEL TELÉFONO QUE VIENE DE LA BASE DE DATOS
        await _abrirWhatsApp(telefonoDestino, mensaje);

        setState(() => items = []); // Limpiamos el carrito localmente
        _mostrarExito();
      } else if (data['error'] == "SIN_STOCK") {
        _mostrarAlertaSinStock(data['message']);
      }
    } catch (e) {
      debugPrint("Error al finalizar: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Error al procesar el pedido")),
      );
    } finally {
      setState(() => cargando = false);
    }
  }

  void _mostrarAlertaSinStock(String mensaje) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 10),
            Text("¡Sin Existencia!"),
          ],
        ),
        content: Text(mensaje),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _obtenerCarrito();
            },
            child: const Text("ACTUALIZAR CARRITO"),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmarVaciarCarrito() async {
    // 1. Mostrar el candado de confirmación
    bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 10),
            Text("¿Vaciar Carrito?"),
          ],
        ),
        content: const Text(
          "¿Estás seguro de que deseas eliminar todos los productos de tu pedido? Esta acción no se puede deshacer.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("CANCELAR", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              "VACIAR AHORA",
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    // 2. Si el usuario dijo que sí, ejecutamos la limpieza
    if (confirmar == true) {
      setState(() => cargando = true);
      try {
        final res = await http.post(
          Uri.parse('${widget.baseUrl}/api/carrito/vaciar'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'ip_add': 'APP_USER'}),
        );

        if (res.statusCode == 200) {
          setState(() {
            items = []; // Limpiamos la lista local
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Carrito vaciado correctamente"),
              backgroundColor: Colors.blueGrey,
            ),
          );
        }
      } catch (e) {
        debugPrint("Error al vaciar: $e");
      } finally {
        setState(() => cargando = false);
      }
    }
  }

  Future<void> _abrirWhatsApp(String telefono, String mensaje) async {
    final telLimpio = telefono.replaceAll(RegExp(r'[^0-9]'), '');
    final whatsappUri = Uri.parse(
      "https://wa.me/$telLimpio?text=${Uri.encodeComponent(mensaje)}",
    );
    if (await canLaunchUrl(whatsappUri)) {
      await launchUrl(whatsappUri, mode: LaunchMode.externalApplication);
    }
  }

  void _mostrarExito() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Icon(Icons.check_circle, color: Colors.green, size: 50),
        content: const Text("¡Pedido procesado!\nSe ha enviado el resumen."),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text("Aceptar"),
          ),
        ],
      ),
    );
  }

  Widget _botonCant(IconData icono, VoidCallback accion) {
    return IconButton(
      onPressed: accion,
      constraints: const BoxConstraints(), // Quita el espacio extra por defecto
      padding: const EdgeInsets.all(8), // Da un área de toque cómoda
      icon: Icon(icono, size: 22, color: Colors.black87),
      style: IconButton.styleFrom(
        backgroundColor: Colors.grey[200],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text(
          "Mi Carrito",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFFD32F2F),
        elevation: 0,
        actions: [
          if (items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep, size: 28),
              tooltip: "Vaciar todo el carrito",
              onPressed:
                  _confirmarVaciarCarrito, // Llamamos a la función de abajo
            ),
        ],
      ),
      body: cargando
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
          ? const Center(
              child: Text(
                "Tu carrito está vacío",
                style: TextStyle(fontSize: 16),
              ),
            )
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  color: Colors.amber[50],
                  child: Row(
                    children: [
                      const Icon(Icons.store, color: Colors.orange, size: 20),
                      const SizedBox(width: 10),
                      Text(
                        "Surtido desde: $nombreSucursal",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      int qty =
                          (double.tryParse(item['qty']?.toString() ?? '1') ?? 1)
                              .toInt();
                      print(
                        "Producto: ${item['Descripcion']} - Sucursal: ${item['num_suc']}",
                      );
                      double precio =
                          double.tryParse(item['p_price']?.toString() ?? '0') ??
                          0;

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Row(
                            children: [
                              // IMAGEN CON ZOOM
                              GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => VerImagenPage(
                                        url:
                                            '${widget.baseUrl}/uploads/${item['Foto']}',
                                      ),
                                    ),
                                  );
                                },
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    '${widget.baseUrl}/uploads/${item['Foto']}',
                                    width: 70,
                                    height: 70,
                                    fit: BoxFit.cover,
                                    errorBuilder: (c, e, s) =>
                                        const Icon(Icons.image, size: 70),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              // DETALLES
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item['Descripcion'],
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      "Precio: ${formatCurrency(precio)}",
                                      style: TextStyle(
                                        color: Colors.grey[700],
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        _botonCant(
                                          Icons.remove,
                                          () => _actualizarCantidad(
                                            item,
                                            qty - 1,
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 15,
                                          ),
                                          child: Text(
                                            "$qty",
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        _botonCant(
                                          Icons.add,
                                          () => _actualizarCantidad(
                                            item,
                                            qty + 1,
                                          ),
                                        ),
                                        const Spacer(),
                                        Text(
                                          formatCurrency(precio * qty),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFFD32F2F),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.grey,
                                ),
                                onPressed: () => _eliminarItem(item['p_id']),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                // RESUMEN Y BOTÓN FIJO
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 10,
                        offset: Offset(0, -5),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            "TOTAL ESTIMADO:",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            formatCurrency(_calcularTotal()),
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFD32F2F),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 15),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFD32F2F),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: _verificarLoginYConfirmar,
                          child: const Text(
                            "CONFIRMAR PEDIDO",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

// PÁGINA PARA VER IMAGEN EN GRANDE
class VerImagenPage extends StatelessWidget {
  final String url;
  const VerImagenPage({super.key, required this.url});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: InteractiveViewer(
          clipBehavior: Clip.none,
          maxScale: 5.0,
          child: Image.network(
            url,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return const CircularProgressIndicator(color: Colors.white);
            },
            errorBuilder: (c, e, s) =>
                const Icon(Icons.broken_image, color: Colors.white, size: 50),
          ),
        ),
      ),
    );
  }
}
