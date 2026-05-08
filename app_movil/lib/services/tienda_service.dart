import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart'; // <--- Agrega esto al principio
import 'package:url_launcher/url_launcher.dart';

class TiendaService {
  // 1. Obtener Categorías
  static Future<List<dynamic>> fetchCategorias(String baseUrl) async {
    final res = await http.get(Uri.parse('$baseUrl/api/tipos'));
    if (res.statusCode == 200) return json.decode(res.body);
    throw Exception("Error al cargar categorías");
  }

  // 2. Obtener Inventario (Híbrido: Búsqueda Potente + Filtro de Tipo)
  static Future<List<dynamic>> fetchInventario({
    required String baseUrl,
    String query = "",
    String categoria = "",
    int page = 0,
    required int idSuc,
    required int seed,
  }) async {
    // Construimos la URL base
    String url =
        '$baseUrl/api/tienda/buscar?page=$page&idSuc=$idSuc&seed=$seed';

    // Solo añadimos 'q' si hay texto real
    if (query.trim().isNotEmpty) {
      url += "&q=${Uri.encodeComponent(query.trim())}";
    }

    // Solo añadimos 'tipo' si hay categoría y no es TODOS
    if (categoria.isNotEmpty && categoria != "TODOS") {
      url += "&tipo=${Uri.encodeComponent(categoria.trim())}";
    }

    final res = await http.get(Uri.parse(url));
    if (res.statusCode == 200) return json.decode(res.body);
    throw Exception("Error en servidor: ${res.statusCode}");
  }

  // 3. Obtener Sucursales (Almacenes)
  static Future<List<dynamic>> fetchSucursales(String baseUrl) async {
    try {
      final url = Uri.parse('$baseUrl/api/sucursales?soloApp=true');
      debugPrint("--- Intentando conectar a: $url ---");

      final res = await http.get(url).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        return json.decode(res.body);
      } else {
        // Esto nos dirá si el servidor respondió con un error (404, 500, etc)
        throw Exception("Servidor respondió con código: ${res.statusCode}");
      }
    } catch (e) {
      // Esto nos dirá si hubo un error de red (Connection refused, timeout, etc)
      debugPrint("Error de red en fetchSucursales: $e");
      throw Exception(
        "Error de conexión: Verifica que tu IP sea correcta y el ProLiant esté encendido.",
      );
    }
  }

  // 4. Contador del Carrito
  static Future<int> getCarritoCount(String baseUrl) async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/carrito/contar?ip_add=APP_USER'),
    );
    if (res.statusCode == 200) {
      final data = json.decode(res.body);
      return int.tryParse(data['total']?.toString() ?? '0') ?? 0;
    }
    return 0;
  }

  // 5. Agregar al Carrito (POST)
  static Future<http.Response> agregarAlCarrito({
    required String baseUrl,
    required dynamic pId,
    required String qty,
    required double price,
    required int idSuc,
  }) async {
    return await http.post(
      Uri.parse('$baseUrl/api/agregar_carrito'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'p_id': pId,
        'qty': qty,
        'p_price': price.toString(),
        'ip_add': 'APP_USER',
        'num_suc': idSuc,
        'is_increment': true,
      }),
    );
  }

  // 6. Vaciar Carrito (POST)
  static Future<void> vaciarCarrito(String baseUrl) async {
    await http.post(
      Uri.parse('$baseUrl/api/carrito/vaciar'),
      body: json.encode({'ip_add': 'APP_USER'}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  // 7. OBTENER MENSAJE DINÁMICO (Para la confirmación final)
  static Future<Map<String, dynamic>> fetchMensaje(
    String baseUrl,
    String slug,
  ) async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/api/mensajes/$slug'));
      debugPrint("Respuesta Mensaje (${res.statusCode}): ${res.body}");
      if (res.statusCode == 200) return json.decode(res.body);
    } catch (e) {
      print("Error al traer mensaje: $e");
    }
    return {};
  }

  // 8. VALIDAR STOCK ANTES DE FINALIZAR
  static Future<Map<String, dynamic>> validarStockFinal(
    String baseUrl,
    List<dynamic> carrito,
    int idSuc,
  ) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/carrito/validar-stock-final'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'items': carrito, 'idSuc': idSuc}),
    );
    return json.decode(res.body);
  }

  // 9. Nuevo método para formatear la URL de Google Drive
  // En lib/services/tienda_service.dart
  static String getImagenUrl(String? driveId) {
    // Si es nulo, vacío o literalmente el texto "null"
    if (driveId == null || driveId.isEmpty || driveId == 'null') {
      return "";
    }
    // Formato optimizado para visualización rápida en Apps
    return "https://lh3.googleusercontent.com/d/$driveId=h1000";
  }

  //obtener url remota
  // El error era el espacio entre 'baseUrl' y 'Actual'
  static Future<String?> obtenerUrlRemota(String baseUrlActual) async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrlActual/api/config/api_url'))
          .timeout(const Duration(seconds: 3));

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        return data['valor'];
      }
    } catch (e) {
      debugPrint("No se pudo verificar URL remota: $e");
    }
    return null;
  }

  // Método centralizado para soporte vía WhatsApp
  static Future<void> contactarSoporteWhatsApp(
    String baseUrl, {
    String? mensajePersonalizado,
  }) async {
    try {
      // Reutilizamos la lógica de obtener el número desde la base de datos
      final res = await http.get(Uri.parse('$baseUrl/api/config/soporte'));

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        String numeroSoporte =
            data['telefono'] ??
            data['TelSoporte'] ??
            "529631320318"; // Respaldo por si acaso

        // Limpiamos el número de caracteres no numéricos
        numeroSoporte = numeroSoporte.replaceAll(RegExp(r'\D'), '');

        // Aseguramos el código de país para México si no lo tiene
        if (!numeroSoporte.startsWith('52')) numeroSoporte = '52$numeroSoporte';

        String mensaje =
            mensajePersonalizado ??
            "Hola Factory Mayoreo, necesito ayuda con la App.";

        final url =
            "https://wa.me/$numeroSoporte?text=${Uri.encodeComponent(mensaje)}";

        if (await canLaunchUrl(Uri.parse(url))) {
          await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        }
      }
    } catch (e) {
      debugPrint("Error al contactar soporte: $e");
    }
  }
}
