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

  @override
  String toString() {
    final codePart = code != null ? ' code=$code,' : '';
    return 'ApiException(status=$statusCode,$codePart message=$message)';
  }
}
