import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart'; // <--- Agrega esto al principio

class TiendaService {
  // 1. Obtener Categorías
  static Future<List<dynamic>> fetchCategorias(String baseUrl) async {
    final res = await http.get(Uri.parse('$baseUrl/api/tipos'));
    if (res.statusCode == 200) return json.decode(res.body);
    throw Exception("Error al cargar categorías");
  }

  // 2. Obtener Inventario (Paginación + Semilla MariaDB)
  static Future<List<dynamic>> fetchInventario({
    required String baseUrl,
    String query = "",
    int page = 0,
    required int idSuc,
    required int seed,
  }) async {
    final res = await http.get(
      Uri.parse(
        '$baseUrl/api/inventario?q=$query&page=$page&idSuc=$idSuc&seed=$seed',
      ),
    );
    if (res.statusCode == 200) return json.decode(res.body);
    throw Exception("Error al cargar inventario");
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
}
