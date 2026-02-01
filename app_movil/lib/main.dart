import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/constants.dart';
import 'screens/tienda_screen.dart';
import 'package:factory_tienda/services/tienda_service.dart';

void main() async {
  // 1. Inicialización necesaria para usar SharedPreferences antes del runApp
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Leemos la URL guardada en la memoria del teléfono
  final prefs = await SharedPreferences.getInstance();

  // 3. Prioridad:
  //    Primero busca la URL manual.
  //    Si no existe, usa la que tengas en AppConfig.baseUrl (tu constante de respaldo).
  String? savedUrl = prefs.getString('custom_api_url');
  String finalUrl = savedUrl ?? AppConfig.baseUrl;

  // 4. Arrancamos pasando la URL definitiva
  runApp(MiNegocioApp(baseUrl: finalUrl));
}

class MiNegocioApp extends StatelessWidget {
  final String baseUrl;

  // Recibimos la baseUrl dinámica
  const MiNegocioApp({super.key, required this.baseUrl});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Factory Mayoreo',
      theme: ThemeData(
        primarySwatch: Colors.red,
        useMaterial3: false,
        primaryColor: const Color(0xFFD32F2F),
      ),
      // Pasamos la URL al RootHandler
      home: RootHandler(baseUrl: baseUrl),
    );
  }
}

class RootHandler extends StatefulWidget {
  final String baseUrl;

  // Recibimos la baseUrl aquí también
  const RootHandler({super.key, required this.baseUrl});

  @override
  State<RootHandler> createState() => _RootHandlerState();
}

class _RootHandlerState extends State<RootHandler> {
  @override
  void initState() {
    super.initState();
    _decidirRuta();
  }

  Future<void> _decidirRuta() async {
    final prefs = await SharedPreferences.getInstance();

    // 1. Lógica de URL Dinámica (VITAL: Se mantiene igual)
    // Esto permite que la app sepa si cambiaste de IP local a Tailscale
    String? urlNueva = await TiendaService.obtenerUrlRemota(widget.baseUrl);
    String urlFinal = widget.baseUrl;

    if (urlNueva != null && urlNueva != widget.baseUrl) {
      // Si la DB dice que la URL cambió, la guardamos y actualizamos
      await prefs.setString('custom_api_url', urlNueva);
      urlFinal = urlNueva;
      debugPrint("--- URL AUTO-ACTUALIZADA: $urlFinal ---");
    }

    // --- LIMPIEZA DE SEGURIDAD ---
    // En la app de Clientes, NO nos importa si hay un admin guardado.
    // Siempre asumimos que es un cliente o invitado.

    if (!mounted) return;

    // 2. Navegación DIRECTA a la Tienda
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => TiendaScreen(baseUrl: urlFinal)),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Pantalla de carga mientras se decide la ruta
    return const Scaffold(
      body: Center(child: CircularProgressIndicator(color: Color(0xFFD32F2F))),
    );
  }
}
