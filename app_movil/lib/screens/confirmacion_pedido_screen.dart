import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ConfirmacionPedidoScreen extends StatefulWidget {
  final String baseUrl;
  final List<dynamic> items;
  final double total;
  final VoidCallback onConfirmar; // La función que dispara el guardado

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

  // Colores corporativos
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
            // 1. TARJETA DE RESUMEN DE ENVÍO
            _buildTarjetaDatosEnvio(),

            const SizedBox(height: 20),

            // 2. TÍTULO DE LISTA
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

            // 3. LISTA DE ITEMS (Simplificada)
            _buildListaProductos(),

            const SizedBox(height: 25),

            // 4. TARJETA DE TOTALES
            _buildTarjetaTotales(),

            const SizedBox(height: 30),

            // 5. BOTÓN FINAL DE ACCIÓN
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
                onPressed: widget.onConfirmar, // <--- DISPARA EL GUARDADO
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
        Text(valor, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildListaProductos() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: ListView.separated(
        shrinkWrap:
            true, // Importante para que funcione dentro de un ScrollView
        physics: const NeverScrollableScrollPhysics(),
        itemCount: widget.items.length,
        separatorBuilder: (ctx, i) => const Divider(height: 1),
        itemBuilder: (ctx, i) {
          final item = widget.items[i];
          final qty = item['qty'];
          final desc = item['Descripcion'];
          final precio = double.tryParse(item['p_price'].toString()) ?? 0;
          final subtotal = qty * precio;

          return ListTile(
            dense: true,
            leading: CircleAvatar(
              backgroundColor: Colors.grey[200],
              radius: 15,
              child: Text(
                "$qty",
                style: TextStyle(
                  color: rojoFactory,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
            title: Text(desc, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: Text(
              "\$${subtotal.toStringAsFixed(2)}",
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          );
        },
      ),
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
              const Text("Total Productos:", style: TextStyle(fontSize: 16)),
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
