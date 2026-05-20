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
  String _telSoporteDinamico = "529631320317"; // CORREGIDO

  // Controladores
  final _telController = TextEditingController();
  final _nombreController = TextEditingController();
  final _emailController = TextEditingController();
  final _calleController = TextEditingController();
  final _barrioController = TextEditingController();
  final _cpController = TextEditingController();
  final _ciudadController = TextEditingController();
  final _estadoController = TextEditingController();

  // Controladores de Contraseña
  final _passAnteriorController = TextEditingController();
  final _passNuevaController = TextEditingController();
  final _passConfirmController = TextEditingController();

  // Visibilidad de contraseñas
  bool _verAnterior = false;
  bool _verNueva = false;
  bool _verConfirm = false;

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
            _cpController.text = (cliente['Cp'] ?? cliente['CP'] ?? "")
                .toString();
            _ciudadController.text = (cliente['Ciudad'] ?? "").toString();
            _estadoController.text = (cliente['Estado'] ?? "").toString();
            if (data['telefonoSoporte'] != null)
              _telSoporteDinamico = data['telefonoSoporte'];
          });
        }
      }
    } catch (e) {
      debugPrint("Error: $e");
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _guardarCambios() async {
    if (!_formKey.currentState!.validate()) return;

    // VERIFICACIÓN LÓGICA: Solo enviamos contraseña si el campo de "Nueva" tiene algo
    bool cambiarPass = _passNuevaController.text.isNotEmpty;

    if (cambiarPass) {
      if (_passAnteriorController.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Debes ingresar tu contraseña actual")),
        );
        return;
      }
      if (_passNuevaController.text != _passConfirmController.text) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Las nuevas contraseñas no coinciden")),
        );
        return;
      }
    }

    setState(() => _guardando = true);

    try {
      final res = await http.put(
        Uri.parse('${widget.baseUrl}/api/cliente/perfil'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'id': _clienteId,
          'nombreCompleto': _nombreController.text.trim(),
          'email': _emailController.text.trim(),
          // Solo enviamos los campos de password si realmente se intentó cambiar
          'passAnterior': cambiarPass
              ? _passAnteriorController.text.trim()
              : '',
          'passNueva': cambiarPass ? _passNuevaController.text.trim() : '',
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
            content: Text(data['message'] ?? "Resultado desconocido"),
            backgroundColor: data['success'] == true
                ? Colors.green
                : Colors.red,
          ),
        );
        if (data['success'] == true) {
          _passAnteriorController.clear();
          _passNuevaController.clear();
          _passConfirmController.clear();
        }
      }
    } catch (e) {
      debugPrint("Error: $e");
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Error de conexión")));
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

  // Widget auxiliar para campos de contraseña con ojo
  Widget _buildPassField(
    TextEditingController ctrl,
    String label,
    bool visible,
    Function(bool) toggle,
  ) {
    return TextFormField(
      controller: ctrl,
      obscureText: !visible,
      maxLength: 10,
      decoration: InputDecoration(
        counterText: "",
        labelText: label,
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          icon: Icon(visible ? Icons.visibility : Icons.visibility_off),
          onPressed: () => toggle(!visible),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(
        title: const Text("Mi Perfil", style: TextStyle(color: Colors.white)),
        backgroundColor: rojoFactory,
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
                decoration: const InputDecoration(
                  labelText: "Teléfono (No editable)",
                  filled: true,
                  border: OutlineInputBorder(),
                ),
              ),
              TextButton(
                onPressed: _solicitarCambioNumero,
                child: const Text("¿Cambiaste de número? Contacta a soporte"),
              ),
              const SizedBox(height: 15),
              TextFormField(
                controller: _nombreController,
                inputFormatters: [
                  UpperCaseTextFormatter(),
                  LengthLimitingTextInputFormatter(60),
                ],
                decoration: const InputDecoration(
                  labelText: "Nombre Completo",
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v!.isEmpty ? "Obligatorio" : null,
              ),
              const SizedBox(height: 15),
              TextFormField(
                controller: _emailController,
                maxLength: 50,
                decoration: const InputDecoration(
                  counterText: "",
                  labelText: "Email",
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  if (v != null &&
                      v.isNotEmpty &&
                      !RegExp(
                        r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$",
                      ).hasMatch(v)) {
                    return "Correo inválido";
                  }
                  return null;
                },
              ),

              // SECCIÓN SEGURIDAD PASSWORD
              const Divider(height: 40, thickness: 1),
              const Text(
                "Cambiar Contraseña",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              _buildPassField(
                _passAnteriorController,
                "Contraseña Actual",
                _verAnterior,
                (v) => setState(() => _verAnterior = v),
              ),
              const SizedBox(height: 10),
              _buildPassField(
                _passNuevaController,
                "Nueva Contraseña",
                _verNueva,
                (v) => setState(() => _verNueva = v),
              ),
              const SizedBox(height: 10),
              _buildPassField(
                _passConfirmController,
                "Confirmar Nueva Contraseña",
                _verConfirm,
                (v) => setState(() => _verConfirm = v),
              ),
              const Divider(height: 40, thickness: 1),

              TextFormField(
                controller: _calleController,
                inputFormatters: [
                  UpperCaseTextFormatter(),
                  LengthLimitingTextInputFormatter(100),
                ],
                decoration: const InputDecoration(
                  labelText: "Calle y Número",
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v!.isEmpty ? "Requerido" : null,
              ),
              const SizedBox(height: 15),
              TextFormField(
                controller: _barrioController,
                inputFormatters: [
                  UpperCaseTextFormatter(),
                  LengthLimitingTextInputFormatter(50),
                ],
                decoration: const InputDecoration(
                  labelText: "Colonia / Barrio",
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v!.isEmpty ? "Requerido" : null,
              ),
              const SizedBox(height: 15),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _ciudadController,
                      inputFormatters: [
                        UpperCaseTextFormatter(),
                        LengthLimitingTextInputFormatter(50),
                      ],
                      decoration: const InputDecoration(
                        labelText: "Ciudad",
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => v!.isEmpty ? "Requerido" : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 1,
                    child: TextFormField(
                      controller: _cpController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [LengthLimitingTextInputFormatter(5)],
                      decoration: const InputDecoration(
                        labelText: "C.P.",
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => v!.isEmpty ? "Requerido" : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              TextFormField(
                controller: _estadoController,
                inputFormatters: [
                  UpperCaseTextFormatter(),
                  LengthLimitingTextInputFormatter(50),
                ],
                decoration: const InputDecoration(
                  labelText: "Estado",
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v!.isEmpty ? "Requerido" : null,
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
