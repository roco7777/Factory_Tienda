class AppConfig {
  static const String baseUrl = "http://34.57.243.117:3000";
  //"https://erma-contributorial-sufferingly.ngrok-free.dev";
}

String formatCurrency(dynamic valor) {
  double monto = double.tryParse(valor.toString()) ?? 0;
  RegExp reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
  String mathFunc(Match match) => '${match[1]},';
  return "\$${monto.toStringAsFixed(2).replaceAllMapped(reg, mathFunc)}";
}
