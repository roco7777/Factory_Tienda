import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/tienda_service.dart';

class ConfirmacionPedidoScreen extends StatefulWidget {
  final String baseUrl;
  final List<dynamic> items;
  final double total;
  final VoidCallback onConfirmar; // Esta función viene del CarritoScreen

  const ConfirmacionPedidoScreen({
    super.key,
    required this.baseUrl,
    required this.items,
    required this.total,
    required this.onConfirmar,
  });

  @override
  State<ConfirmacionPedidoScreen> createState() =>
      _ConfirmacionPedidoScreenState();
}

class _ConfirmacionPedidoScreenState extends State<ConfirmacionPedidoScreen> {
  String clienteNombre = "Cargando...";
  String sucursalNombre = "Cargando...";

  final Color rojoFactory = const Color(0xFFD32F2F);
  final Color grisFondo = const Color(0xFFF5F5F5);

  @override
  void initState() {
    super.initState();
    _cargarDatosUsuario();
  }

  Future<void> _cargarDatosUsuario() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      clienteNombre = prefs.getString('cliente_nombre') ?? "Cliente Invitado";
      sucursalNombre = prefs.getString('saved_sucursal_nombre') ?? "Sucursal";
    });
  }

  // --- FUNCIÓN PARA VER FOTO (OPTIMIZADA) ---
  void _mostrarFotoProducto(dynamic item) {
    // 1. Extraemos el drive_id del objeto item
    String driveId = (item['drive_id'] ?? item['DriveID'])?.toString() ?? '';
    String descripcion = item['Descripcion'] ?? 'Producto';

    if (driveId.isEmpty || driveId == 'null') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Este producto no tiene imagen en Drive")),
      );
      return;
    }

    // 2. Usamos nuestra función maestra de TiendaService
    final String urlFoto = TiendaService.getImagenUrl(driveId);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(descripcion, style: const TextStyle(fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              constraints: const BoxConstraints(maxHeight: 350),
              width: double.maxFinite,
              child: Image.network(
                urlFoto,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return const Center(child: CircularProgressIndicator());
                },
                errorBuilder: (ctx, error, stackTrace) => const Icon(
                  Icons.broken_image,
                  size: 80,
                  color: Colors.grey,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("Cerrar"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: grisFondo,
      appBar: AppBar(
        title: const Text("Confirmar Pedido"),
        backgroundColor: rojoFactory,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTarjetaDatosEnvio(),
            const SizedBox(height: 20),
            const Text(
              "RESUMEN DE PRODUCTOS",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey,
                fontSize: 12,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            _buildListaProductos(),
            const SizedBox(height: 25),
            _buildTarjetaTotales(),
            const SizedBox(height: 30),

            // --- BOTÓN CONFIRMAR ---
            SizedBox(
              height: 55,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[700],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 4,
                ),
                // Aquí llamamos a la función que nos pasó el padre (CarritoScreen)
                onPressed: widget.onConfirmar,
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "CONFIRMAR Y HACER PEDIDO",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(width: 10),
                    Icon(Icons.check_circle_outline, color: Colors.white),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 15),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                "Volver y modificar carrito",
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTarjetaDatosEnvio() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Row(
              children: [
                Icon(Icons.local_shipping_outlined, color: Colors.orange),
                SizedBox(width: 10),
                Text(
                  "Datos de Surtido",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const Divider(height: 25),
            _buildFilaDato("Cliente:", clienteNombre),
            const SizedBox(height: 10),
            _buildFilaDato("Almacén Origen:", sucursalNombre),
            const SizedBox(height: 10),
            _buildFilaDato("Tipo de Entrega:", "A coordinar por WhatsApp"),
          ],
        ),
      ),
    );
  }

  Widget _buildFilaDato(String label, String valor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey)),
        Flexible(
          child: Text(
            valor,
            style: const TextStyle(fontWeight: FontWeight.w600),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }

  Widget _buildListaProductos() {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: widget.items.length,
      itemBuilder: (ctx, i) {
        final item = widget.items[i];

        final qty = double.tryParse(item['qty'].toString()) ?? 0;
        final desc = item['Descripcion'] ?? 'Producto';
        final precio = double.tryParse(item['p_price'].toString()) ?? 0;
        final subtotal = qty * precio;

        // Obtenemos el nombre REAL del archivo de la BD
        final String driveId =
            (item['drive_id'] ?? item['DriveID'])?.toString() ?? '';

        return Card(
          elevation: 1,
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: InkWell(
            onTap: () => _mostrarFotoProducto(item),
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                children: [
                  Container(
                    width: 45,
                    height: 45,
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: driveId.isNotEmpty && driveId != 'null'
                          ? Image.network(
                              TiendaService.getImagenUrl(driveId),
                              fit: BoxFit.cover,
                              errorBuilder: (ctx, err, stack) => const Icon(
                                Icons.broken_image,
                                size: 20,
                                color: Colors.grey,
                              ),
                              loadingBuilder: (ctx, child, progress) {
                                if (progress == null) return child;
                                return const Center(
                                  child: SizedBox(
                                    width: 15,
                                    height: 15,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                );
                              },
                            )
                          : const Icon(
                              Icons.no_photography,
                              color: Colors.grey,
                              size: 20,
                            ),
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          desc,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        // Cantidad en Rojo y sin decimales
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.red.shade100),
                          ),
                          child: Text(
                            "${qty.toStringAsFixed(0)} x \$${precio.toStringAsFixed(2)}",
                            style: TextStyle(
                              fontSize: 14,
                              color: rojoFactory,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        "Subtotal",
                        style: TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                      Text(
                        "\$${subtotal.toStringAsFixed(2)}",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.green.shade700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTarjetaTotales() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey[300]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Total Artículos:", style: TextStyle(fontSize: 16)),
              Text(
                "${widget.items.length}",
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const Divider(height: 30),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "TOTAL A PAGAR",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              Text(
                "\$${widget.total.toStringAsFixed(2)}",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: rojoFactory,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
