import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'tienda_screen.dart';
import 'login_screen.dart';
import '../services/tienda_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class SplashScreen extends StatefulWidget {
  final String baseUrl;
  const SplashScreen({super.key, required this.baseUrl});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _inicializarApp();
  }

  Future<void> _inicializarApp() async {
    try {
      // 1. Configurar Notificaciones (Fires and forgets, no detiene el arranque)
      _setupNotifications().catchError(
        (e) => debugPrint("Error FCM Setup: $e"),
      );

      final prefs = await SharedPreferences.getInstance();

      // Intentamos recuperar una URL personalizada previa si existe
      String? savedUrl = prefs.getString('custom_api_url');
      String urlFinal = savedUrl ?? widget.baseUrl;

      // 2. LÓGICA DE ACTUALIZACIÓN DE URL (Con paracaídas)
      try {
        // Consultamos al servidor si hay una nueva dirección, con tope de 4 segundos
        String? urlNueva = await TiendaService.obtenerUrlRemota(
          urlFinal,
        ).timeout(const Duration(seconds: 4));

        if (urlNueva != null && urlNueva.isNotEmpty && urlNueva != urlFinal) {
          await prefs.setString('custom_api_url', urlNueva);
          urlFinal = urlNueva;
          debugPrint("--- URL AUTO-ACTUALIZADA: $urlFinal ---");
        }
      } catch (e) {
        // Si el servidor no responde o no hay red, seguimos con la URL que ya tenemos
        debugPrint(
          "Aviso: No se pudo verificar actualización de URL (Usando actual): $e",
        );
      }

      // 3. Pausa estética para que el usuario vea el logo rojo
      await Future.delayed(const Duration(milliseconds: 1500));

      // 4. REVISAR SESIÓN (CORREGIDO: Leemos como String)
      // Como en tu LoginScreen usas prefs.setString('cliente_id', ...), aquí leemos String
      final String? clienteId = prefs.getString('cliente_id');

      if (!mounted) return;

      // NAVEGACIÓN FINAL
      if (clienteId != null && clienteId.isNotEmpty) {
        debugPrint("Sesión detectada. Cliente ID: $clienteId");
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => TiendaScreen(baseUrl: urlFinal)),
        );
      } else {
        debugPrint("Sin sesión activa. Mandando al Login.");
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => LoginScreen(baseUrl: urlFinal)),
        );
      }
    } catch (globalError) {
      // Si ocurre un error catastrófico no previsto
      debugPrint("Error crítico en proceso de Splash: $globalError");
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => LoginScreen(baseUrl: widget.baseUrl),
          ),
        );
      }
    }
  }

  Future<void> _setupNotifications() async {
    try {
      FirebaseMessaging messaging = FirebaseMessaging.instance;
      NotificationSettings settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        await messaging.subscribeToTopic('todos');
      }
    } catch (e) {
      debugPrint("Error en configuración de notificaciones: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    // Convertimos tu código #ED3237 al formato de Flutter
    const Color rojoExactoFactory = Color(0xFFED3237);

    return Scaffold(
      backgroundColor: rojoExactoFactory, // Ahora sí, el color idéntico
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo con tamaño optimizado
            Image.asset(
              'assets/images/logo_factory.png',
              // Usamos el 75% del ancho de la pantalla para que se vea genial
              width: MediaQuery.of(context).size.width * 0.75,
              fit: BoxFit.contain,
            ),

            const SizedBox(height: 40),

            // Indicador de carga blanco para que resalte
            const CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 3,
            ),
          ],
        ),
      ),
    );
  }
}
