class AppConfig {
  static const String baseUrl = "https://factorymayoreo.com/api";
}

String formatCurrency(dynamic valor) {
  double monto = double.tryParse(valor.toString()) ?? 0;
  RegExp reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
  String mathFunc(Match match) => '${match[1]},';
  return "\$${monto.toStringAsFixed(2).replaceAllMapped(reg, mathFunc)}";
}
