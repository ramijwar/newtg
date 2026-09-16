final class ApiException implements Exception {
  const ApiException({
    required this.message,
    this.code,
    this.requestId,
    this.statusCode,
  });

  final String message;
  final String? code;
  final String? requestId;
  final int? statusCode;

  @override
  String toString() => 'ApiException($code, $statusCode): $message';
}
