import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}

class PerfilScreen extends StatefulWidget {
  final String baseUrl;
  const PerfilScreen({super.key, required this.baseUrl});

  @override
  State<PerfilScreen> createState() => _PerfilScreenState();
}

class _PerfilScreenState extends State<PerfilScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _cargando = true;
  bool _guardando = false;
  String _clienteId = "";
  String _telSoporteDinamico = "529631320318";

  final _telController = TextEditingController();
  final _nombreController = TextEditingController();
  final _emailController = TextEditingController();
  final _calleController = TextEditingController();
  final _barrioController = TextEditingController();
  final _cpController = TextEditingController();
  final _ciudadController = TextEditingController();
  final _estadoController = TextEditingController();

  final Color rojoFactory = const Color(0xFFD32F2F);

  @override
  void initState() {
    super.initState();
    _cargarDatosPerfil();
  }

  Future<void> _cargarDatosPerfil() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _clienteId = prefs.getString('cliente_id') ?? "";

      if (_clienteId.isEmpty) return;

      final res = await http.get(
        Uri.parse('${widget.baseUrl}/api/cliente/perfil?id=$_clienteId'),
      );

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data['success'] == true) {
          final cliente = data['cliente'];
          setState(() {
            _telController.text = (cliente['Cel'] ?? "").toString();
            _nombreController.text = (cliente['Nombre2'] ?? "").toString();
            _emailController.text = (cliente['email'] ?? "").toString();
            _calleController.text = (cliente['Calle'] ?? "").toString();
            _barrioController.text = (cliente['Barrio'] ?? "").toString();
            // Validamos Cp o CP por el detalle que encontramos
            _cpController.text = (cliente['Cp'] ?? cliente['CP'] ?? "")
                .toString();
            _ciudadController.text = (cliente['Ciudad'] ?? "").toString();
            _estadoController.text = (cliente['Estado'] ?? "").toString();

            if (data['telefonoSoporte'] != null) {
              _telSoporteDinamico = data['telefonoSoporte'];
            }
          });
        }
      }
    } catch (e) {
      debugPrint("Error cargando perfil: $e");
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _guardarCambios() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _guardando = true);

    try {
      final res = await http.put(
        Uri.parse('${widget.baseUrl}/api/cliente/perfil'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'id': _clienteId,
          'nombreCompleto': _nombreController.text.trim(),
          'email': _emailController.text.trim(),
          'direccion': _calleController.text.trim(),
          'colonia': _barrioController.text.trim(),
          'cp': _cpController.text.trim(),
          'ciudad': _ciudadController.text.trim(),
          'estado': _estadoController.text.trim(),
        }),
      );

      final data = json.decode(res.body);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['message'] ?? "Perfil actualizado"),
            backgroundColor: data['success'] ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      debugPrint("Error guardando: $e");
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _solicitarCambioNumero() async {
    String mensaje =
        "Hola, soy ${_nombreController.text}. Necesito actualizar mi número ${_telController.text}.";
    final url =
        "https://wa.me/$_telSoporteDinamico?text=${Uri.encodeComponent(mensaje)}";
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Mi Perfil", style: TextStyle(color: Colors.white)),
        backgroundColor: rojoFactory,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _telController,
                readOnly: true,
                decoration: InputDecoration(
                  labelText: "Teléfono (No editable)",
                  prefixIcon: const Icon(Icons.lock),
                  filled: true,
                  fillColor: Colors.grey[200],
                  border: const OutlineInputBorder(),
                ),
              ),
              TextButton(
                onPressed: _solicitarCambioNumero,
                child: const Text("¿Cambiaste de número? Contacta a soporte"),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _nombreController,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [UpperCaseTextFormatter()],
                decoration: const InputDecoration(
                  labelText: "Nombre Completo",
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v!.isEmpty ? "Campo obligatorio" : null,
              ),
              const SizedBox(height: 15),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: "Email",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 15),
              TextFormField(
                controller: _calleController,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [UpperCaseTextFormatter()],
                decoration: const InputDecoration(
                  labelText: "Calle y Número",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 15),
              TextFormField(
                controller: _barrioController,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [UpperCaseTextFormatter()],
                decoration: const InputDecoration(
                  labelText: "Colonia / Barrio",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 15),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _ciudadController,
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [UpperCaseTextFormatter()],
                      decoration: const InputDecoration(
                        labelText: "Ciudad",
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 1,
                    child: TextFormField(
                      controller: _cpController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: "C.P.",
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              TextFormField(
                controller: _estadoController,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [UpperCaseTextFormatter()],
                decoration: const InputDecoration(
                  labelText: "Estado",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: rojoFactory),
                  onPressed: _guardando ? null : _guardarCambios,
                  child: _guardando
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          "GUARDAR CAMBIOS",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
