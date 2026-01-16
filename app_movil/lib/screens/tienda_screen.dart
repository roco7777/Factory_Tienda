import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';
import 'carrito_screen.dart';
import 'inventario_screen.dart';
import 'login_screen.dart';
import 'admin_login_screen.dart';
import 'package:audioplayers/audioplayers.dart';

class TiendaScreen extends StatefulWidget {
  final String baseUrl;
  const TiendaScreen({super.key, required this.baseUrl});

  @override
  State<TiendaScreen> createState() => _TiendaScreenState();
}

class _TiendaScreenState extends State<TiendaScreen> {
  List<dynamic> productos = [];
  List<dynamic> categorias = [];
  List<dynamic> sucursales = [];
  dynamic sucursalActual;
  String? nombreCliente;
  String? rolAdmin;

  String nombreSucursal = "Sucursal";

  String categoriaSeleccionada = "TODOS";
  bool cargando = false;
  int totalItemsCarrito = 0;
  int sucursalSeleccionada = 1;

  final ScrollController _scrollController = ScrollController();
  int _paginaActual = 0;
  bool _cargandoMas = false;
  bool _hayMasProductos = true;

  final TextEditingController buscadorCtrl = TextEditingController();
  final Color rojoFactory = const Color(0xFFD32F2F);

  @override
  void initState() {
    super.initState();
    _cargarSesion();
    _cargarSucursales();
    _actualizarContadorCarrito();

    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 300) {
        if (!_cargandoMas && _hayMasProductos && !cargando) {
          _cargarMasProductos();
        }
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    buscadorCtrl.dispose();
    super.dispose();
  }

  // Carga el nombre del cliente y el rol de admin si existen
  Future<void> _cargarSesion() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      String nombreCompleto = prefs.getString('cliente_nombre') ?? "Invitado";
      // Si el nombre tiene espacios, tomamos solo la primera palabra
      nombreCliente = nombreCompleto.split(' ')[0];
      rolAdmin = prefs.getString('saved_rol');
    });
  }

  Future<void> _cargarDatosIniciales() async {
    if (cargando || !mounted) return;
    setState(() => cargando = true);

    try {
      // 1. Cargamos categorías solo si están vacías para ahorrar peticiones
      if (categorias.isEmpty) {
        final resCat = await http.get(Uri.parse('${widget.baseUrl}/api/tipos'));
        if (resCat.statusCode == 200) {
          setState(() => categorias = json.decode(resCat.body));
        }
      }

      // 2. Cargamos inventario
      // 1. AGREGA ESTA LÍNEA (Define qué vamos a buscar al inicio)
      String busqueda = categoriaSeleccionada == "TODOS"
          ? ""
          : categoriaSeleccionada;

      // 2. AHORA SÍ, USA LA VARIABLE 'busqueda'
      final response = await http.get(
        Uri.parse(
          '${widget.baseUrl}/api/inventario?q=$busqueda&page=0&idSuc=$sucursalSeleccionada',
        ),
      );

      // ELIMINAMOS el debugPrint del body completo.
      // Solo imprimimos el conteo para saber si funcionó.
      if (response.statusCode == 200) {
        List<dynamic> data = json.decode(response.body);
        setState(() {
          productos = data;
          _paginaActual = 0;
          _hayMasProductos = data.length >= 10;
        });

        // --- TURBO DE PRE-CARGA ---
        // El S24 Ultra tiene RAM de sobra, vamos a usarla
        for (var prod in data) {
          if (prod['Foto'] != null && prod['Foto'] != "") {
            // Pre-cargamos la imagen completa en la memoria
            precacheImage(
              NetworkImage('${widget.baseUrl}/uploads/${prod['Foto']}'),
              context,
            );
          }
        }
      }
    } catch (e) {
      debugPrint("Error cargando datos: $e");
    } finally {
      if (mounted) setState(() => cargando = false);
    }
  }

  Future<void> _cargarSucursales() async {
    try {
      final res = await http.get(
        Uri.parse('${widget.baseUrl}/api/sucursales?soloApp=true'),
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);

        final prefs = await SharedPreferences.getInstance();
        int? savedId = prefs.getInt('saved_sucursal_id');
        String? savedNombre = prefs.getString('saved_sucursal_nombre');

        setState(() {
          sucursales = data;
          if (sucursales.isNotEmpty) {
            if (savedId != null) {
              // Si hay una guardada, intentamos encontrarla en la lista que bajó de la API
              sucursalActual = sucursales.firstWhere(
                (s) =>
                    (s['ID'] ?? s['id'] ?? s['Id']).toString() ==
                    savedId.toString(),
                orElse: () =>
                    sucursales[0], // Si no la encuentra, usa la primera
              );
              sucursalSeleccionada = savedId;
              nombreSucursal = savedNombre ?? "Sucursal";
            } else {
              // Si es la primera vez (no hay nada guardado), usa la primera por defecto
              sucursalActual = sucursales[0];
              var rawId =
                  sucursalActual['ID'] ??
                  sucursalActual['id'] ??
                  sucursalActual['Id'];
              sucursalSeleccionada = int.tryParse(rawId.toString()) ?? 1;
              nombreSucursal = sucursalActual['sucursal'] ?? "Sucursal";
            }
          }
        });
        _cargarDatosIniciales();
      }
    } catch (e) {
      debugPrint("Error sucursales: $e");
    }
  }

  void _mostrarModalSucursales() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      // Evita que el modal sea demasiado alto en pantallas grandes como el S24 Ultra
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        // Limitamos la altura máxima al 70% de la pantalla para evitar cálculos infinitos
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min, // La columna solo ocupa lo necesario
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                "Selecciona un Almacén",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
            const Divider(height: 1),
            // Usamos Flexible en lugar de shrinkWrap para permitir el scroll eficiente
            Flexible(
              child: ListView.builder(
                shrinkWrap:
                    false, // ¡IMPORTANTE! Desactivado para ganar fluidez
                itemCount: sucursales.length,
                itemBuilder: (context, i) {
                  final suc = sucursales[i];
                  return ListTile(
                    leading: const Icon(Icons.store, color: Color(0xFFD32F2F)),
                    title: Text(
                      suc['sucursal'] ?? 'Sucursal sin nombre',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: const Text("Toca para ver detalles de envío"),
                    onTap: () {
                      Navigator.pop(context);
                      _mostrarInfoSucursal(suc);
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  void _mostrarInfoSucursal(dynamic suc) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Row(
          children: [
            Icon(Icons.local_shipping, color: rojoFactory),
            const SizedBox(width: 10),
            Expanded(child: Text(suc['sucursal'] ?? 'Información de Envío')),
          ],
        ),
        content: SingleChildScrollView(
          child: Text(
            suc['InfoEnvio'] ??
                "No hay descripción de envío disponible para esta sucursal.",
            style: const TextStyle(fontSize: 14, height: 1.4),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CERRAR"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: rojoFactory),
            onPressed: () {
              Navigator.pop(context);
              _cambiarSucursal(suc);
            },
            child: const Text(
              "SELECCIONAR ALMACÉN",
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _cambiarSucursal(dynamic suc) async {
    // 1. Obtenemos la instancia de memoria
    final prefs = await SharedPreferences.getInstance();

    var rawId = suc['ID'] ?? suc['id'] ?? suc['Id'];
    int id = int.tryParse(rawId.toString()) ?? 1;
    String nombre = suc['sucursal'] ?? "Sucursal";

    // 2. Guardamos permanentemente
    await prefs.setInt('saved_sucursal_id', id);
    await prefs.setString('saved_sucursal_nombre', nombre);

    setState(() {
      sucursalActual = suc;
      sucursalSeleccionada = id;
      nombreSucursal = nombre;
      productos = [];
      _paginaActual = 0;
    });
    _cargarDatosIniciales();
  }

  Future<void> _actualizarContadorCarrito() async {
    try {
      final res = await http.get(
        Uri.parse('${widget.baseUrl}/api/carrito/contar?ip_add=APP_USER'),
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        int nuevoTotal = int.tryParse(data['total']?.toString() ?? '0') ?? 0;

        // SOLO hacemos setState si el número CAMBIÓ realmente
        if (nuevoTotal != totalItemsCarrito) {
          setState(() => totalItemsCarrito = nuevoTotal);
        }
      }
    } catch (e) {
      debugPrint("Error contador: $e");
    }
  }

  Future<void> _cargarMasProductos() async {
    if (_cargandoMas || !_hayMasProductos) return;
    setState(() => _cargandoMas = true);
    _paginaActual++;
    try {
      String busqueda = categoriaSeleccionada == "TODOS"
          ? ""
          : categoriaSeleccionada;
      final response = await http.get(
        Uri.parse(
          '${widget.baseUrl}/api/inventario?q=$busqueda&page=$_paginaActual&idSuc=$sucursalSeleccionada',
        ),
      );
      if (response.statusCode == 200) {
        List<dynamic> nuevos = json.decode(response.body);
        setState(() {
          _hayMasProductos = nuevos.length >= 10;
          productos.addAll(nuevos);
        });
      }
    } finally {
      setState(() => _cargandoMas = false);
    }
  }

  // --- AGREGAR ESTA DEFINICIÓN ---
  final AudioPlayer _audioPlayer = AudioPlayer();

  Future<void> _reproducirBip() async {
    try {
      await _audioPlayer.play(AssetSource('sounds/beep.mp3'));
    } catch (e) {
      debugPrint("Error al reproducir sonido: $e");
    }
  }

  Future<void> buscarProductos(String query) async {
    setState(() {
      cargando = true;
      _paginaActual = 0;
      _hayMasProductos = true;
      productos = [];
    });
    try {
      final response = await http.get(
        Uri.parse(
          '${widget.baseUrl}/api/inventario?q=$query&page=0&idSuc=$sucursalSeleccionada',
        ),
      );
      if (response.statusCode == 200) {
        List<dynamic> data = json.decode(response.body);
        setState(() {
          productos = data;
          _hayMasProductos = data.length >= 10;
        });
        if (data.isNotEmpty) {
          buscadorCtrl.clear();
        }
      }
    } finally {
      setState(() => cargando = false);
    }
  }

  Future<void> _guardarEnCarrito(dynamic pId, String qty, double price) async {
    try {
      final res = await http.post(
        Uri.parse('${widget.baseUrl}/api/agregar_carrito'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'p_id': pId,
          'qty': qty,
          'p_price': price.toString(),
          'ip_add': 'APP_USER',
          'num_suc': sucursalSeleccionada,
          'is_increment': true,
        }),
      );

      if (res.statusCode == 200) {
        if (mounted) Navigator.pop(context); // Éxito: Cerramos modal
        _reproducirBip();
        _actualizarContadorCarrito();
      } else {
        final errorData = json.decode(res.body);

        if (errorData['error'] == "DIFERENTE_SUCURSAL") {
          _mostrarAlertaVaciarCarrito();
        } else {
          // --- NUEVO: Alerta de Stock que sí se ve ---
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text("Atención"),
              content: Text(errorData['message'] ?? "Sin stock"),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("ACEPTAR"),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("Error: $e");
    }
  }

  void _mostrarFichaProducto(dynamic item) {
    FocusScope.of(context).unfocus();

    // Usamos PageRouteBuilder para controlar EXACTAMENTE la animación
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (context, animation, secondaryAnimation) =>
            FichaProductoPage(
              item: item,
              baseUrl: widget.baseUrl,
              rojoFactory: rojoFactory,
              onAgregar: (itemSeleccionado) =>
                  _mostrarSelectorCantidad(itemSeleccionado),
            ),
        // Esta es la clave: Usamos un FadeTransition en lugar del zoom de Android
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  void _mostrarAlertaVaciarCarrito() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Carrito con otra sucursal"),
        content: const Text(
          "Tu carrito contiene productos de otro almacén. ¿Deseas vaciarlo?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CANCELAR"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await http.post(
                Uri.parse('${widget.baseUrl}/api/carrito/vaciar'),
                body: json.encode({'ip_add': 'APP_USER'}),
                headers: {'Content-Type': 'application/json'},
              );
              Navigator.pop(context);
              _actualizarContadorCarrito();
            },
            child: const Text("VACIAR Y CONTINUAR"),
          ),
        ],
      ),
    );
  }

  Future<void> _cerrarSesion() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('cliente_id');
    await prefs.remove('cliente_nombre');

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Sesión cerrada correctamente")),
    );

    setState(() {
      // En lugar de null, lo ponemos como Invitado directamente
      nombreCliente = "Invitado";
    });

    // Esto recargará las preferencias y confirmará que todo está limpio
    _cargarSesion();
  }

  void _mostrarDialogoCerrarSesion() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Cerrar Sesión"),
        content: Text("¿$nombreCliente, seguro que deseas salir de tu cuenta?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("NO"),
          ),
          TextButton(
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              // Borramos los datos del cliente
              await prefs.remove('cliente_id');
              await prefs.remove('cliente_nombre');

              if (!mounted) return;
              Navigator.pop(context); // Cerramos el diálogo
              setState(() {
                nombreCliente = "Invitado";
              });
              // Refrescamos la sesión para que cambie a "Invitado"
              _cargarSesion();

              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text("Sesión cerrada")));
            },
            child: const Text(
              "CERRAR SESIÓN",
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _mostrarSelectorCantidad(dynamic item) {
    TextEditingController cantCtrl = TextEditingController(text: "1");
    double p1 = double.tryParse(item['Precio1']?.toString() ?? '0') ?? 0.0;
    double p2 = double.tryParse(item['Precio2']?.toString() ?? '0') ?? 0.0;
    double p3 = double.tryParse(item['Precio3']?.toString() ?? '0') ?? 0.0;
    int min2 = (double.tryParse(item['Min2']?.toString() ?? '0') ?? 0).toInt();
    int min3 = (double.tryParse(item['Min3']?.toString() ?? '0') ?? 0).toInt();

    // --- NUEVO: Extraemos el stock que viene del servidor ---
    int stockDisponible =
        int.tryParse(item['stock_disponible']?.toString() ?? '0') ?? 0;

    double precioCalculado = p1;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item['Descripcion'] ?? '',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              // --- NUEVO: Indicador visual de stock ---
              const SizedBox(height: 5),
              Text(
                "Stock disponible: $stockDisponible pzas",
                style: TextStyle(
                  fontSize: 13,
                  color: stockDisponible > 0 ? Colors.blueGrey : Colors.red,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: cantCtrl,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: "Cantidad",
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) {
                  int c = int.tryParse(v) ?? 0;
                  setModalState(() {
                    if (c >= min3 && min3 > 0)
                      precioCalculado = p3;
                    else if (c >= min2 && min2 > 0)
                      precioCalculado = p2;
                    else
                      precioCalculado = p1;
                  });
                },
              ),
              const SizedBox(height: 15),
              Text(
                "Precio: ${formatCurrency(precioCalculado)}",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: rojoFactory,
                ),
              ),
              const SizedBox(height: 15),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: rojoFactory),
                  onPressed: () {
                    // --- EL CANDADO DE SEGURIDAD ---
                    int cant = int.tryParse(cantCtrl.text) ?? 0;

                    // 1. Validar que sea mayor a 0
                    if (cant <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("La cantidad debe ser mayor a cero"),
                          backgroundColor: Colors.orange,
                        ),
                      );
                      return;
                    }

                    // 2. Validar que no supere el stock
                    if (cant > stockDisponible) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            "Solo hay $stockDisponible unidades disponibles",
                          ),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }

                    // Si pasa los filtros, guardamos
                    _guardarEnCarrito(
                      item['Id'],
                      cant.toString(),
                      precioCalculado,
                    );
                  },
                  child: const Text(
                    "AGREGAR AL CARRITO",
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      drawer: rolAdmin != null
          ? Drawer(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  DrawerHeader(
                    decoration: BoxDecoration(color: rojoFactory),
                    child: const Text(
                      "Opciones de Admin",
                      style: TextStyle(color: Colors.white, fontSize: 20),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.inventory),
                    title: const Text("Panel de Inventario"),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => PantallaInventario(
                            userRole: rolAdmin!,
                            baseUrl: widget.baseUrl,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            )
          : null,
      appBar: AppBar(
        backgroundColor: rojoFactory,
        foregroundColor: Colors.white,
        title: GestureDetector(
          onLongPress: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => AdminLoginScreen(baseUrl: widget.baseUrl),
              ),
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Factory Mayoreo",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
              ),
              // Sucursal actual
              Row(
                children: [
                  const Icon(Icons.storefront, size: 12, color: Colors.white70),
                  const SizedBox(width: 4),
                  Text(
                    nombreSucursal,
                    style: const TextStyle(fontSize: 10, color: Colors.white70),
                  ),
                ],
              ),
              // Nombre del cliente DEBAJO
              Text(
                (nombreCliente == null || nombreCliente == "Invitado")
                    ? "Hola invitado"
                    : "Hola, $nombreCliente",
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        actions: [
          // 1. EL CARRITO (Ahora primero)
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.shopping_cart),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          CarritoScreen(baseUrl: widget.baseUrl),
                    ),
                  ).then((_) => _actualizarContadorCarrito());
                },
              ),
              if (totalItemsCarrito > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 14,
                      minHeight: 14,
                    ),
                    child: Text(
                      '$totalItemsCarrito',
                      style: const TextStyle(
                        color: Colors.red,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          // 2. ICONO DE SUCURSAL (Si existe)
          if (sucursales.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.location_on, size: 22),
              onPressed:
                  _mostrarModalSucursales, // Asegúrate de que esta sea tu función
            ),
          // 3. CERRAR SESIÓN (Ahora al final)
          IconButton(
            icon: Icon(
              // Si es invitado, mostramos un icono de "Usuario/Perfil" para invitar a entrar
              // Si ya inició sesión, mostramos el icono clásico de "Salir"
              nombreCliente == "Invitado"
                  ? Icons.account_circle_outlined
                  : Icons.exit_to_app,
              size: 26, // Lo hacemos un poco más grande para que se vea mejor
            ),
            tooltip: nombreCliente == "Invitado"
                ? "Iniciar Sesión"
                : "Cerrar Sesión",
            onPressed: () {
              if (nombreCliente == "Invitado") {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => LoginScreen(baseUrl: widget.baseUrl),
                  ),
                ).then((_) => _cargarSesion());
              } else {
                _mostrarDialogoCerrarSesion();
              }
            },
          ),
        ],
        bottom: PreferredSize(
          // Reducimos la altura de 110 a 90 para que sea más delgada
          preferredSize: const Size.fromHeight(95),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 4,
                ),
                child: SizedBox(
                  height: 40, // Altura fija más delgada para el buscador
                  child: TextField(
                    controller: buscadorCtrl,
                    textAlignVertical: TextAlignVertical.center,
                    decoration: InputDecoration(
                      hintText: "Buscar productos...",
                      hintStyle: const TextStyle(fontSize: 13),
                      prefixIcon: const Icon(Icons.search, size: 20),
                      fillColor: Colors.white,
                      filled: true,
                      isDense: true, // Hace la caja más compacta
                      contentPadding: EdgeInsets.zero,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (val) => buscarProductos(val),
                  ),
                ),
              ),
              // Selector de categorías (también un poco más compacto)
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _buildCatItem("TODOS"),
                    ...categorias.map((c) => _buildCatItem(c['Descripcion'])),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: cargando && productos.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : productos.isEmpty
                ? const Center(child: Text("Sin stock en este almacén"))
                : GridView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(8),
                    // PROPIEDADES DE FLUIDEZ:
                    physics:
                        const AlwaysScrollableScrollPhysics(), // Scroll más natural
                    cacheExtent:
                        250, // Pre-carga solo una pequeña parte (ahorra RAM)
                    addAutomaticKeepAlives:
                        false, // No mantiene vivos los que no se ven
                    addRepaintBoundaries: true,

                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio:
                          0.52, // Ajusta este valor si ves que se corta el botón
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: productos.length,
                    itemBuilder: (context, index) {
                      // Usamos const o widgets estables para que no parpadee
                      return _buildProductCard(productos[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCatItem(String nombre) {
    bool seleccionada = categoriaSeleccionada == nombre;
    return GestureDetector(
      onTap: () {
        setState(() => categoriaSeleccionada = nombre);
        buscarProductos(nombre == "TODOS" ? "" : nombre);
      },
      child: Container(
        margin: const EdgeInsets.all(8),
        padding: const EdgeInsets.symmetric(horizontal: 15),
        decoration: BoxDecoration(
          color: seleccionada ? Colors.white : Colors.white24,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Center(
          child: Text(
            nombre,
            style: TextStyle(
              color: seleccionada ? rojoFactory : Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProductCard(dynamic item) {
    // Extraemos precios y mínimos con la misma lógica que la ficha detallada
    double p1 = double.tryParse(item['Precio1']?.toString() ?? '0') ?? 0.0;
    double p2 = double.tryParse(item['Precio2']?.toString() ?? '0') ?? 0.0;
    double p3 = double.tryParse(item['Precio3']?.toString() ?? '0') ?? 0.0;
    int m1 = (double.tryParse(item['Min1']?.toString() ?? '1') ?? 1).toInt();
    int m2 = (double.tryParse(item['Min2']?.toString() ?? '0') ?? 0).toInt();
    int m3 = (double.tryParse(item['Min3']?.toString() ?? '0') ?? 0).toInt();

    int preciosActivos = 0;
    if (p1 > 0) preciosActivos++;
    if (p2 > 0) preciosActivos++;
    if (p3 > 0) preciosActivos++;

    return Card(
      elevation: 4,
      child: Column(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => _mostrarFichaProducto(item),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(4),
                ),
                child:
                    item['Foto'] != null && item['Foto'].toString().isNotEmpty
                    ? Image.network(
                        '${widget.baseUrl}/uploads/${item['Foto']}',
                        fit: BoxFit.cover,
                        width: double.infinity,
                        cacheWidth: 300, // Seguimos optimizando memoria
                        cacheHeight: 300,

                        // EFECTO FADE-IN
                        frameBuilder:
                            (context, child, frame, wasSynchronouslyLoaded) {
                              if (wasSynchronouslyLoaded) return child;
                              return AnimatedOpacity(
                                opacity: frame == null ? 0 : 1,
                                duration: const Duration(
                                  milliseconds: 500,
                                ), // Medio segundo de suavizado
                                curve: Curves.easeIn,
                                child: child,
                              );
                            },
                        errorBuilder: (c, e, s) => const Icon(
                          Icons.image_not_supported,
                          color: Colors.grey,
                        ),
                      )
                    : const Icon(Icons.image, size: 50),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['Descripcion'] ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                Text(
                  "Cve: ${item['Clave']}",
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.black,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Divider(color: Colors.black12),

                // --- LÓGICA DE PRECIOS IGUAL A LA FICHA DETALLADA ---
                if (preciosActivos == 1)
                  _buildPrecioFila("Precio:", p1, Colors.black, false)
                else ...[
                  if (p1 > 0)
                    _buildPrecioFila(
                      "A partir de $m1 pzas:",
                      p1,
                      Colors.black,
                      false,
                    ),
                  if (p2 > 0)
                    _buildPrecioFila(
                      "A partir de $m2 pzas:",
                      p2,
                      rojoFactory,
                      false,
                    ),
                  if (p3 > 0)
                    _buildPrecioFila(
                      "A partir de $m3 pzas:",
                      p3,
                      const Color(0xFF388E3C),
                      false,
                    ),
                ],

                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  height: 35,
                  child: ElevatedButton(
                    onPressed: () => _mostrarSelectorCantidad(item),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: rojoFactory,
                    ),
                    child: const Text(
                      "AGREGAR",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
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

  Widget _buildPrecioFila(String label, double price, Color col, bool esFicha) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: esFicha ? 6 : 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: esFicha ? 16 : 9,
              color: Colors.black,
              fontWeight: esFicha ? FontWeight.bold : FontWeight.w500,
            ),
          ),
          Text(
            formatCurrency(price),
            style: TextStyle(
              fontSize: esFicha ? 26 : 14,
              fontWeight: FontWeight.bold,
              color: col,
            ),
          ),
        ],
      ),
    );
  }
} // Cierre de la clase _TiendaScreenState

class FichaProductoPage extends StatelessWidget {
  final dynamic item;
  final String baseUrl;
  final Color rojoFactory;
  final Function(dynamic) onAgregar;

  const FichaProductoPage({
    super.key,
    required this.item,
    required this.baseUrl,
    required this.rojoFactory,
    required this.onAgregar,
  });

  @override
  Widget build(BuildContext context) {
    // Reutilizamos tu lógica de precios
    double p1 = double.tryParse(item['Precio1']?.toString() ?? '0') ?? 0.0;
    double p2 = double.tryParse(item['Precio2']?.toString() ?? '0') ?? 0.0;
    double p3 = double.tryParse(item['Precio3']?.toString() ?? '0') ?? 0.0;
    int m1 = (double.tryParse(item['Min1']?.toString() ?? '1') ?? 1).toInt();
    int m2 = (double.tryParse(item['Min2']?.toString() ?? '0') ?? 0).toInt();
    int m3 = (double.tryParse(item['Min3']?.toString() ?? '0') ?? 0).toInt();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black),
          onPressed: () async {
            // Cerramos el teclado si estuviera abierto
            FocusScope.of(context).unfocus();
            // Le damos un respiro de 50ms antes de iniciar la salida
            await Future.delayed(const Duration(milliseconds: 50));
            if (context.mounted) Navigator.pop(context);
          },
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: InteractiveViewer(
              child: Center(
                child:
                    item['Foto'] != null && item['Foto'].toString().isNotEmpty
                    ? Image.network(
                        '$baseUrl/uploads/${item['Foto']}',
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      )
                    : const Icon(Icons.image, size: 100, color: Colors.grey),
              ),
            ),
          ),
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
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item['Descripcion'] ?? '',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 15),
                // Aquí podrías llamar a una función similar a _buildPrecioFila
                // Para simplificar esta prueba, puedes poner los precios directos o el widget
                _buildPrecioFilaLocal("Precio:", p1, Colors.black),
                if (p2 > 0)
                  _buildPrecioFilaLocal(
                    "A partir de $m2 pzas:",
                    p2,
                    rojoFactory,
                  ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: rojoFactory,
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      onAgregar(item);
                    },
                    child: const Text(
                      "AGREGAR AL PEDIDO",
                      style: TextStyle(color: Colors.white, fontSize: 16),
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

  Widget _buildPrecioFilaLocal(String label, double price, Color col) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        Text(
          "\$${price.toStringAsFixed(2)}",
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: col,
          ),
        ),
      ],
    );
  }
}
