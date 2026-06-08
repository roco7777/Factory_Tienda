import 'package:flutter/material.dart';
import '../services/tienda_service.dart'; // Asegúrate de que la ruta sea correcta

class DetalleProductoScreen extends StatefulWidget {
  final List<dynamic> productos;
  final int initialIndex;
  final String baseUrl;
  final Function(dynamic) onAgregarTap;

  const DetalleProductoScreen({
    super.key,
    required this.productos,
    required this.initialIndex,
    required this.baseUrl,
    required this.onAgregarTap,
  });

  @override
  State<DetalleProductoScreen> createState() => _DetalleProductoScreenState();
}

class _DetalleProductoScreenState extends State<DetalleProductoScreen> {
  late PageController _pageController;
  late int
  _currentIndex; // Guardamos el índice actual para ocultar/mostrar flechas

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Detalle de Producto"),
        backgroundColor: Colors.red[800],
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      // STACK: Nos permite poner las flechas flotando encima del PageView
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            // Cada vez que el usuario desliza, actualizamos el índice
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            physics: const BouncingScrollPhysics(),
            itemCount: widget.productos.length,
            itemBuilder: (context, index) {
              final item = widget.productos[index];

              String productDesc = item['product_desc']?.toString() ?? "";

              double p1 =
                  double.tryParse(item['Precio1']?.toString() ?? '0') ?? 0;
              double p2 =
                  double.tryParse(item['Precio2']?.toString() ?? '0') ?? 0;
              double p3 =
                  double.tryParse(item['Precio3']?.toString() ?? '0') ?? 0;

              int m1 = (double.tryParse(item['Min1']?.toString() ?? '1') ?? 1)
                  .toInt();
              int m2 = (double.tryParse(item['Min2']?.toString() ?? '0') ?? 0)
                  .toInt();
              int m3 = (double.tryParse(item['Min3']?.toString() ?? '0') ?? 0)
                  .toInt();

              int preciosActivos =
                  (p1 > 0 ? 1 : 0) + (p2 > 0 ? 1 : 0) + (p3 > 0 ? 1 : 0);

              // --- CORRECCIÓN 1: AGREGAMOS NULL Y WIDGET.BASEURL ---
              String driveId =
                  (item['drive_id'] ?? item['DriveID'])?.toString() ?? '';
              String imageUrl = TiendaService.getImagenUrl(
                driveId,
                null,
                widget.baseUrl,
              );

              return SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: () {
                        if (imageUrl.isNotEmpty) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => FullScreenImageView(
                                imageUrl: imageUrl,
                                clave: item['Clave'],
                                tagId: item['Id'] ?? item['Clave'],
                              ),
                            ),
                          );
                        }
                      },
                      child: Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          Container(
                            width: double.infinity,
                            height: 380,
                            color: Colors.grey[50],
                            // --- CORRECCIÓN 2: QUITAMOS EL HERO WIDGET AQUÍ ---
                            child: imageUrl.isNotEmpty
                                ? Image.network(
                                    imageUrl,
                                    fit: BoxFit.contain,
                                    loadingBuilder:
                                        (context, child, loadingProgress) {
                                          if (loadingProgress == null)
                                            return child;
                                          return Center(
                                            child: CircularProgressIndicator(
                                              color: Colors.red[800],
                                              value:
                                                  loadingProgress
                                                          .expectedTotalBytes !=
                                                      null
                                                  ? loadingProgress
                                                            .cumulativeBytesLoaded /
                                                        loadingProgress
                                                            .expectedTotalBytes!
                                                  : null,
                                            ),
                                          );
                                        },
                                    errorBuilder:
                                        (context, error, stackTrace) => Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons
                                                  .image_not_supported_outlined,
                                              size: 80,
                                              color: Colors.grey[400],
                                            ),
                                            const SizedBox(height: 10),
                                            Text(
                                              "Imagen no disponible",
                                              style: TextStyle(
                                                color: Colors.grey[500],
                                              ),
                                            ),
                                          ],
                                        ),
                                  )
                                : Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.cloud_off,
                                          size: 80,
                                          color: Colors.grey[300],
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          "Sin enlace a Drive",
                                          style: TextStyle(
                                            color: Colors.grey[400],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                          ),
                          if (imageUrl.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(30),
                                ),
                                child: const Icon(
                                  Icons.zoom_in,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                    Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item['Descripcion'] ?? "",
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Clave: ${item['Clave'] ?? 'N/A'}",
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.black54,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 15),

                          if (productDesc.isNotEmpty &&
                              productDesc != "null") ...[
                            const Text(
                              "INFORMACIÓN ADICIONAL",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.grey,
                                fontSize: 11,
                                letterSpacing: 1.1,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              productDesc,
                              style: const TextStyle(
                                fontSize: 15,
                                color: Colors.black87,
                                height: 1.4,
                              ),
                            ),
                          ],

                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 15),
                            child: Divider(color: Colors.black12),
                          ),

                          const Text(
                            "LISTA DE PRECIOS",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 10),

                          if (preciosActivos == 1)
                            _buildFilaPrecio("Precio:", p1, Colors.red, 22)
                          else ...[
                            if (p1 > 0)
                              _buildFilaPrecio(
                                "A partir de $m1 pzas:",
                                p1,
                                Colors.red,
                                20,
                              ),
                            if (p2 > 0)
                              _buildFilaPrecio(
                                "A partir de $m2 pzas:",
                                p2,
                                Colors.green[700]!,
                                20,
                              ),
                            if (p3 > 0)
                              _buildFilaPrecio(
                                "A partir de $m3 pzas:",
                                p3,
                                Colors.blue[700]!,
                                20,
                              ),
                          ],

                          const SizedBox(height: 30),

                          SizedBox(
                            width: double.infinity,
                            height: 55,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pop(context);
                                widget.onAgregarTap(item);
                              },
                              icon: const Icon(
                                Icons.shopping_cart_checkout,
                                color: Colors.white,
                              ),
                              label: const Text(
                                "AGREGAR AL PEDIDO",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red[800],
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 4,
                              ),
                            ),
                          ),
                          const SizedBox(height: 30),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          // --- FLECHA IZQUIERDA ---
          if (_currentIndex > 0)
            Align(
              alignment: const Alignment(
                -1.0,
                -0.3,
              ), // Posición sobre la imagen
              child: Padding(
                padding: const EdgeInsets.only(left: 10.0),
                child: _buildBotonNavegacion(
                  icon: Icons.arrow_back_ios_new,
                  onTap: () {
                    _pageController.previousPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  },
                ),
              ),
            ),

          // --- FLECHA DERECHA ---
          if (_currentIndex < widget.productos.length - 1)
            Align(
              alignment: const Alignment(1.0, -0.3), // Posición sobre la imagen
              child: Padding(
                padding: const EdgeInsets.only(right: 10.0),
                child: _buildBotonNavegacion(
                  icon: Icons.arrow_forward_ios,
                  onTap: () {
                    _pageController.nextPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBotonNavegacion({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.25), // Fondo semitransparente
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white.withOpacity(0.9), size: 24),
      ),
    );
  }

  Widget _buildFilaPrecio(
    String label,
    double price,
    Color color,
    double size,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 14, color: Colors.black54),
          ),
          Text(
            "\$${price.toStringAsFixed(2)}",
            style: TextStyle(
              fontSize: size,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// --- WIDGET PARA PANTALLA COMPLETA ---
class FullScreenImageView extends StatelessWidget {
  final String imageUrl;
  final String? clave;
  final dynamic tagId;

  const FullScreenImageView({
    super.key,
    required this.imageUrl,
    this.clave,
    this.tagId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white, size: 30),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SizedBox.expand(
        child: InteractiveViewer(
          panEnabled: true,
          minScale: 1.0,
          maxScale: 5.0,
          // --- CORRECCIÓN 3: QUITAMOS EL HERO WIDGET AQUÍ TAMBIÉN ---
          child: Image.network(
            imageUrl,
            fit: BoxFit.contain,
            alignment: Alignment.center,
          ),
        ),
      ),
    );
  }
}
