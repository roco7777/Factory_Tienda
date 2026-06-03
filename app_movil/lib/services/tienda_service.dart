import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart'; // <-- Agregado para leer el ID

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
    String url =
        '$baseUrl/api/tienda/buscar?page=$page&idSuc=$idSuc&seed=$seed';

    if (query.trim().isNotEmpty) {
      url += "&q=${Uri.encodeComponent(query.trim())}";
    }
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
      final res = await http.get(url).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        return json.decode(res.body);
      } else {
        throw Exception("Servidor respondió con código: ${res.statusCode}");
      }
    } catch (e) {
      throw Exception(
        "Error de conexión: Verifica que tu IP sea correcta y el servidor esté encendido.",
      );
    }
  }

  // 4. Contador del Carrito
  static Future<int> getCarritoCount(String baseUrl) async {
    final prefs = await SharedPreferences.getInstance();
    final String clienteId = prefs.getString('cliente_id') ?? '0';

    final res = await http.get(
      Uri.parse('$baseUrl/api/carrito/contar?ip_add=$clienteId'),
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
    final prefs = await SharedPreferences.getInstance();
    final String clienteId = prefs.getString('cliente_id') ?? '0';

    return await http.post(
      Uri.parse('$baseUrl/api/agregar_carrito'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'p_id': pId,
        'qty': qty,
        'p_price': price.toString(),
        'ip_add': clienteId,
        'num_suc': idSuc,
        'is_increment': true,
      }),
    );
  }

  // 6. Vaciar Carrito (POST)
  static Future<void> vaciarCarrito(String baseUrl) async {
    final prefs = await SharedPreferences.getInstance();
    final String clienteId = prefs.getString('cliente_id') ?? '0';

    await http.post(
      Uri.parse('$baseUrl/api/carrito/vaciar'),
      body: json.encode({'ip_add': clienteId}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  // 7. OBTENER MENSAJE DINÁMICO
  static Future<Map<String, dynamic>> fetchMensaje(
    String baseUrl,
    String slug,
  ) async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/api/mensajes/$slug'));
      if (res.statusCode == 200) return json.decode(res.body);
    } catch (e) {
      debugPrint("Error al traer mensaje: $e");
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

  // 9. Formatear la URL de Google Drive o Servidor Local (CORREGIDO)
  // Ahora fotoLocal y baseUrl son opcionales usando corchetes []
  static String getImagenUrl(
    String? driveId, [
    String? fotoLocal,
    String? baseUrl,
  ]) {
    if (driveId != null && driveId.isNotEmpty && driveId != 'null') {
      return "https://drive.google.com/uc?id=$driveId";
    } else if (fotoLocal != null &&
        fotoLocal.isNotEmpty &&
        fotoLocal != 'null' &&
        baseUrl != null) {
      return "$baseUrl/uploads/$fotoLocal";
    }
    return "";
  }

  // 10. Obtener URL remota
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

  // 11. Consultar las redes sociales
  static Future<List<dynamic>> fetchRedesSociales(String baseUrl) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/social-media'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return data['data'];
        }
      }
      return [];
    } catch (e) {
      debugPrint("Error redes sociales: $e");
      return [];
    }
  }

  // 12. Método centralizado para soporte vía WhatsApp dinámico
  static Future<void> contactarSoporteWhatsApp(
    String baseUrl, {
    String? mensajePersonalizado,
  }) async {
    try {
      String numeroSoporte = "529993271099";

      final res = await http
          .get(Uri.parse('$baseUrl/api/config/soporte'))
          .timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data['telefono'] != null &&
            data['telefono'].toString().isNotEmpty) {
          numeroSoporte = data['telefono'].toString();
        }
      }

      numeroSoporte = numeroSoporte.replaceAll(RegExp(r'\D'), '');

      if (!numeroSoporte.startsWith('52') && numeroSoporte.length == 10) {
        numeroSoporte = '52$numeroSoporte';
      }

      String mensaje =
          mensajePersonalizado ??
          "Hola Factory Mayoreo, necesito ayuda con la App.";
      final url =
          "https://wa.me/$numeroSoporte?text=${Uri.encodeComponent(mensaje)}";

      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } else {
        debugPrint("No se pudo abrir WhatsApp.");
      }
    } catch (e) {
      debugPrint("Error al contactar soporte: $e");
    }
  }
}
