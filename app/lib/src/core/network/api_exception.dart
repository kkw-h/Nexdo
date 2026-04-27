class ApiException implements Exception {
  const ApiException({
    required this.statusCode,
    this.code,
    this.message,
    this.details,
  });

  final int statusCode;
  final int? code;
  final String? message;
  final dynamic details;

  bool get isUnauthorized => statusCode == 401 || code == 40100;

  bool get isValidationError => statusCode == 400 || code == 40000;

  bool get isIncorrectOldPassword => code == 40101;

  bool get isNotFound => statusCode == 404 || code == 40400;

  bool get isConflict =>
      statusCode == 409 || (code != null && code! >= 40900 && code! < 50000);

  bool get isServerError =>
      statusCode >= 500 || (code != null && code! >= 50000);

  @override
  String toString() {
    final codePart = code != null ? ' code=$code,' : '';
    return 'ApiException(status=$statusCode,$codePart message=$message)';
  }
}
