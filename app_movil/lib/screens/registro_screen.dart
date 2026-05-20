import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/tienda_service.dart';

bool _mostrarValidacionExtra = false;

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

enum PasoRegistro {
  pedirTelefono,
  pedirCodigo,
  llenarFormularioCompleto,
  crearSoloContrasena,
}

class RegistroScreen extends StatefulWidget {
  final String baseUrl;
  final bool esRecuperacion;

  const RegistroScreen({
    super.key,
    required this.baseUrl,
    this.esRecuperacion = false,
  });

  @override
  State<RegistroScreen> createState() => _RegistroScreenState();
}

class _RegistroScreenState extends State<RegistroScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _telController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  final TextEditingController _nombreController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _calleController = TextEditingController();
  final TextEditingController _barrioController = TextEditingController();
  final TextEditingController _cpController = TextEditingController();
  final TextEditingController _ciudadController = TextEditingController();
  final TextEditingController _estadoController = TextEditingController();
  final TextEditingController _ultimosCuatroController =
      TextEditingController();

  PasoRegistro _pasoActual = PasoRegistro.pedirTelefono;
  bool _cargando = false;
  bool _verPassword = false;
  String _verificationId = "";

  final Color rojoFactory = const Color(0xFFD32F2F);

  void _mostrarAlertaSeguridad(String msg, String telSoporte) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("Validación de Identidad"),
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("REGRESAR"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () => _contactarSoporte(telSoporte),
            child: const Text(
              "WHATSAPP SOPORTE",
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _contactarSoporte(String numeroSoporte) {
    String mensaje =
        "Hola Factory, mi nombre es ${_nombreController.text}. "
        "Tengo problemas para registrar mi número ${_telController.text}. ¿Podrían ayudarme?";

    TiendaService.contactarSoporteWhatsApp(
      widget.baseUrl,
      mensajePersonalizado: mensaje,
    );
  }

  Future<void> _verificarNumeroYEnviarSMS() async {
    String telefono = _telController.text.trim();
    if (telefono.length < 10) {
      _mostrarAlerta("Ingresa un número válido de 10 dígitos");
      return;
    }

    setState(() {
      _cargando = true;
      _mostrarValidacionExtra = false;
      _ultimosCuatroController.clear();
    });

    try {
      String telefonoLimpio = telefono.replaceAll(' ', '');
      final res = await http.post(
        Uri.parse('${widget.baseUrl}/api/cliente/verificar-numero'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'telefono': telefonoLimpio}),
      );

      final data = json.decode(res.body);
      bool existe = data['existe'] ?? false;
      bool tienePassword = data['tienePassword'] ?? false;

      if (existe && data['datos'] != null) {
        final d = data['datos'];
        setState(() {
          _nombreController.text = d['nombre'] ?? '';
          _emailController.text = d['email'] ?? '';
          _calleController.text = d['calle'] ?? '';
          _barrioController.text = d['barrio'] ?? '';
          _cpController.text = d['cp'] ?? '';
          _ciudadController.text = d['ciudad'] ?? '';
          _estadoController.text = d['estado'] ?? '';
        });
      }

      if (widget.esRecuperacion) {
        if (!existe) {
          _mostrarAlerta("Este número no está registrado.");
          setState(() => _cargando = false);
          return;
        }
        _iniciarAutenticacionFirebase(PasoRegistro.crearSoloContrasena);
      } else {
        if (existe && tienePassword) {
          _mostrarAlerta("Ya tienes cuenta. Por favor inicia sesión.");
          setState(() => _cargando = false);
          return;
        } else if (existe && !tienePassword) {
          _mostrarAlerta(
            "¡Hola ${_nombreController.text}! Identificamos tu número. Te enviaremos un SMS para activar tu cuenta.",
            color: Colors.blue,
          );
          _iniciarAutenticacionFirebase(PasoRegistro.crearSoloContrasena);
        } else {
          _iniciarAutenticacionFirebase(PasoRegistro.llenarFormularioCompleto);
        }
      }
    } catch (e) {
      _mostrarAlerta("Error: ${e.toString()}");
      setState(() => _cargando = false);
    }
  }

  Future<void> _registrarClienteNuevo() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _cargando = true);

    try {
      final res = await http.post(
        Uri.parse('${widget.baseUrl}/api/cliente/registrar'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'nombreCompleto': _nombreController.text.trim(),
          'email': _emailController.text.trim(),
          'password': _passController.text.trim(),
          'telefono': _telController.text.trim(),
          'direccion': _calleController.text.trim(),
          'colonia': _barrioController.text.trim(),
          'cp': _cpController.text.trim(),
          'ciudad': _ciudadController.text.trim(),
          'estado': _estadoController.text.trim(),
          'ultimosCuatroAnterior': _ultimosCuatroController.text.trim(),
        }),
      );

      final data = json.decode(res.body);

      if (data['success'] == true) {
        _terminarExito(data['message'] ?? "¡Registro exitoso!");
      } else {
        if (data['requiereValidacion'] == true) {
          setState(() {
            _mostrarValidacionExtra = true;
          });
          _mostrarAlerta(data['message'], color: Colors.blue);
        } else if (data['error'] == "VALIDACION_FALLIDA" ||
            data['error'] == "SEGURIDAD_BLOQUEO") {
          String telDinamico = data['telefonoSoporte'] ?? "529630000000";
          _mostrarAlertaSeguridad(data['message'], telDinamico);
        } else {
          _mostrarAlerta(data['message'] ?? "Error en el registro");
        }
      }
    } catch (e) {
      _mostrarAlerta("Error de conexión: ${e.toString()}");
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _iniciarAutenticacionFirebase(PasoRegistro siguientePaso) async {
    String numeroConCodigo = "+52${_telController.text.trim()}";
    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: numeroConCodigo,
        verificationCompleted: (PhoneAuthCredential credential) async {
          await _validarCredencialFinal(credential, siguientePaso);
        },
        verificationFailed: (FirebaseAuthException e) {
          setState(() => _cargando = false);
          _mostrarAlerta("Error al enviar SMS: ${e.message}");
        },
        codeSent: (String verificationId, int? resendToken) {
          setState(() {
            _cargando = false;
            _verificationId = verificationId;
            _pasoActual = PasoRegistro.pedirCodigo;
          });
          _mostrarAlerta("Código enviado por SMS", color: Colors.green);
        },
        codeAutoRetrievalTimeout: (String verificationId) {},
      );
    } catch (e) {
      setState(() => _cargando = false);
      _mostrarAlerta("Error crítico: $e");
    }
  }

  Future<void> _validarCodigoOTP(PasoRegistro pasoDestino) async {
    if (_otpController.text.trim().length < 6) {
      _mostrarAlerta("Ingresa el código completo de 6 dígitos");
      return;
    }
    setState(() => _cargando = true);
    try {
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: _verificationId,
        smsCode: _otpController.text.trim(),
      );
      await _validarCredencialFinal(credential, pasoDestino);
    } catch (e) {
      setState(() => _cargando = false);
      _mostrarAlerta("Código incorrecto o expirado");
    }
  }

  Future<void> _validarCredencialFinal(
    PhoneAuthCredential credential,
    PasoRegistro siguientePaso,
  ) async {
    try {
      await FirebaseAuth.instance.signInWithCredential(credential);
      setState(() {
        _cargando = false;
        _pasoActual = siguientePaso;
      });
    } catch (e) {
      setState(() => _cargando = false);
      _mostrarAlerta("Código incorrecto");
    }
  }

  Future<void> _guardarSoloContrasena() async {
    if (_passController.text.trim().length < 4) {
      _mostrarAlerta("La contraseña debe tener mínimo 4 caracteres");
      return;
    }
    setState(() => _cargando = true);
    String endpoint = widget.esRecuperacion
        ? '/api/cliente/reset-password'
        : '/api/cliente/crear-password';

    try {
      final res = await http.post(
        Uri.parse('${widget.baseUrl}$endpoint'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'telefono': _telController.text.trim(),
          widget.esRecuperacion ? 'nuevaPassword' : 'password': _passController
              .text
              .trim(),
        }),
      );
      final data = json.decode(res.body);
      if (data['success'] == true) {
        _terminarExito("Contraseña guardada correctamente.");
      } else {
        _mostrarAlerta(data['message'] ?? "Error al guardar");
      }
    } catch (e) {
      _mostrarAlerta("Error: ${e.toString()}");
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.esRecuperacion ? "Recuperar Contraseña" : "Crear Cuenta",
        ),
        backgroundColor: rojoFactory,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: _construirPantallaPorPaso(),
        ),
      ),
    );
  }

  Widget _buildFormularioCompleto() {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          const Text(
            "¡Número Verificado! Completa tus datos",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Colors.green,
            ),
          ),
          const SizedBox(height: 20),

          TextFormField(
            controller: _nombreController,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [UpperCaseTextFormatter()],
            decoration: const InputDecoration(
              labelText: "Nombre Completo",
              prefixIcon: Icon(Icons.person),
              border: OutlineInputBorder(),
            ),
            validator: (v) => v!.isEmpty ? "Obligatorio" : null,
          ),
          const SizedBox(height: 15),

          TextFormField(
            controller: _emailController,
            maxLength: 50,
            decoration: const InputDecoration(
              counterText: "", // <--- CORREGIDO AQUÍ
              labelText: "Correo Electrónico (Opcional)",
              prefixIcon: Icon(Icons.email),
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.emailAddress,
            validator: (v) {
              if (v != null && v.isNotEmpty) {
                bool emailValido = RegExp(
                  r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+",
                ).hasMatch(v);
                if (!emailValido) {
                  return "Ingresa un correo electrónico válido";
                }
              }
              return null;
            },
          ),
          const SizedBox(height: 15),

          TextFormField(
            controller: _passController,
            obscureText: !_verPassword,
            maxLength: 10,
            decoration: InputDecoration(
              counterText: "", // <--- CORREGIDO AQUÍ
              labelText: "Crea una Contraseña",
              helperText:
                  "Máx. 10 caracteres alfanuméricos. Acepta mayúsculas, minúsculas y caracteres especiales.",
              helperMaxLines: 2,
              prefixIcon: const Icon(Icons.lock),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(
                  _verPassword ? Icons.visibility : Icons.visibility_off,
                  color: Colors.grey,
                ),
                onPressed: () => setState(() => _verPassword = !_verPassword),
              ),
            ),
            validator: (v) => v!.length < 4 ? "Mínimo 4 caracteres" : null,
          ),

          const SizedBox(height: 20),
          const Text(
            "Dirección de Envío",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 10),

          TextFormField(
            controller: _calleController,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [UpperCaseTextFormatter()],
            decoration: const InputDecoration(
              labelText: "Calle y Número",
              border: OutlineInputBorder(),
            ),
            validator: (v) => v!.isEmpty ? "Requerido" : null,
          ),
          const SizedBox(height: 10),

          TextFormField(
            controller: _barrioController,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [UpperCaseTextFormatter()],
            decoration: const InputDecoration(
              labelText: "Colonia / Barrio",
              border: OutlineInputBorder(),
            ),
            validator: (v) => v!.isEmpty ? "Requerido" : null,
          ),
          const SizedBox(height: 10),

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
                  validator: (v) => v!.isEmpty ? "Requerido" : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 1,
                child: TextFormField(
                  controller: _cpController,
                  decoration: const InputDecoration(
                    labelText: "C.P.",
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) => v!.isEmpty ? "Requerido" : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          TextFormField(
            controller: _estadoController,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [UpperCaseTextFormatter()],
            decoration: const InputDecoration(
              labelText: "Estado",
              border: OutlineInputBorder(),
            ),
            validator: (v) => v!.isEmpty ? "Requerido" : null,
          ),

          if (_mostrarValidacionExtra) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                border: Border.all(color: Colors.blue),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  const Text(
                    "YA EXISTE UNA CUENTA CON TU NOMBRE Y UN TELEFONO DIFERENTE",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  const Text(
                    "Ingresa los últimos 4 dígitos de tu cel anterior:",
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _ultimosCuatroController,
                    maxLength: 4,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      counterText: "", // <--- CORREGIDO AQUÍ
                      border: OutlineInputBorder(),
                      fillColor: Colors.white,
                      filled: true,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 30),

          _cargando
              ? const CircularProgressIndicator()
              : SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: rojoFactory,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _registrarClienteNuevo,
                    child: const Text(
                      "REGISTRARME",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildPasoTelefono() {
    return Column(
      children: [
        const Icon(Icons.phone_android, size: 80, color: Colors.grey),
        const SizedBox(height: 20),
        Text(
          widget.esRecuperacion
              ? "Ingresa tu celular para recuperar tu acceso."
              : "Ingresa tu celular para comenzar. Te enviaremos un código de seguridad.",
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16),
        ),
        const SizedBox(height: 30),
        TextField(
          controller: _telController,
          keyboardType: TextInputType.phone,
          maxLength: 10,
          decoration: const InputDecoration(
            counterText: "", // <--- CORREGIDO AQUÍ
            labelText: "Teléfono a 10 dígitos",
            prefixText: "+52 ",
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 20),
        _cargando
            ? const CircularProgressIndicator()
            : SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: rojoFactory,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _verificarNumeroYEnviarSMS,
                  child: const Text(
                    "ENVIAR SMS",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ),
      ],
    );
  }

  Widget _buildPasoCodigo() {
    return Column(
      children: [
        const Icon(Icons.sms, size: 80, color: Colors.blueGrey),
        const SizedBox(height: 20),
        const Text(
          "Ingresa el código de 6 dígitos que te enviamos.",
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 30),
        TextField(
          controller: _otpController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 24,
            letterSpacing: 5,
            fontWeight: FontWeight.bold,
          ),
          decoration: const InputDecoration(
            counterText: "", // <--- CORREGIDO AQUÍ
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 20),
        _cargando
            ? const CircularProgressIndicator()
            : SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueGrey,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    PasoRegistro destino = widget.esRecuperacion
                        ? PasoRegistro.crearSoloContrasena
                        : PasoRegistro.llenarFormularioCompleto;
                    _validarCodigoOTP(destino);
                  },
                  child: const Text(
                    "VERIFICAR CÓDIGO",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ),
      ],
    );
  }

  Widget _buildCrearSoloClave() {
    return Column(
      children: [
        const Icon(Icons.lock_open, size: 80, color: Colors.green),
        const SizedBox(height: 20),
        const Text(
          "¡Identidad Verificada!",
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.green,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          widget.esRecuperacion
              ? "Ingresa tu nueva contraseña para acceder."
              : "Ya eres cliente. Solo crea una contraseña para usar la App.",
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 30),
        TextField(
          controller: _passController,
          obscureText: !_verPassword,
          maxLength: 10,
          decoration: InputDecoration(
            counterText: "", // <--- CORREGIDO AQUÍ
            labelText: "Contraseña",
            helperText:
                "Máx. 10 caracteres alfanuméricos. Acepta mayúsculas, minúsculas y caracteres especiales.",
            helperMaxLines: 2,
            prefixIcon: const Icon(Icons.lock),
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(
                _verPassword ? Icons.visibility : Icons.visibility_off,
                color: Colors.grey,
              ),
              onPressed: () => setState(() => _verPassword = !_verPassword),
            ),
          ),
        ),
        const SizedBox(height: 30),
        _cargando
            ? const CircularProgressIndicator()
            : SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: rojoFactory,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _guardarSoloContrasena,
                  child: const Text(
                    "GUARDAR CONTRASEÑA",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ),
      ],
    );
  }

  Widget _construirPantallaPorPaso() {
    switch (_pasoActual) {
      case PasoRegistro.pedirTelefono:
        return _buildPasoTelefono();
      case PasoRegistro.pedirCodigo:
        return _buildPasoCodigo();
      case PasoRegistro.llenarFormularioCompleto:
        return _buildFormularioCompleto();
      case PasoRegistro.crearSoloContrasena:
        return _buildCrearSoloClave();
    }
  }

  void _mostrarAlerta(String msg, {Color color = Colors.red}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _terminarExito(String msg) {
    if (!mounted) return;
    _mostrarAlerta(msg, color: Colors.green);
    Navigator.pop(context);
  }
}
