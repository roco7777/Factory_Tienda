import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/constants.dart';
import 'package:factory_tienda/services/tienda_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:factory_tienda/screens/splash_screen.dart';

// 1. Manejador de notificaciones (Debe estar aquí afuera para que funcione)
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  print("Mensaje recibido en segundo plano: ${message.messageId}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializamos Firebase con tus credenciales
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Activamos el receptor de mensajes cuando la app está cerrada
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  final prefs = await SharedPreferences.getInstance();

  // Mantenemos tu lógica de prioridad de URL (Vital para Tailscale/IP Fija)
  String? savedUrl = prefs.getString('custom_api_url');
  String finalUrl = savedUrl ?? AppConfig.baseUrl;

  runApp(MiNegocioApp(baseUrl: finalUrl));
}

class MiNegocioApp extends StatelessWidget {
  final String baseUrl;
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
      // Enviamos al usuario a la Splash Screen primero
      home: SplashScreen(baseUrl: baseUrl),
    );
  }
}
