import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../storage/secure_session.dart';
import 'api_exception.dart';

final class ApiClient {
  ApiClient(this._sessionStore)
    : _dio = Dio(
        BaseOptions(
          baseUrl: AppConfig.apiBaseUrl,
          connectTimeout: AppConfig.requestTimeout,
          receiveTimeout: AppConfig.requestTimeout,
          sendTimeout: AppConfig.requestTimeout,
          headers: const {'Accept': 'application/json'},
          validateStatus: (status) => status != null && status < 600,
        ),
      );

  final Dio _dio;
  final SecureSessionStore _sessionStore;

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
  }) => _request('GET', path, query: query);

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
    String? idempotencyKey,
  }) => _request('POST', path, body: body, idempotencyKey: idempotencyKey);

  Future<Map<String, dynamic>> patch(
    String path, {
    Map<String, dynamic>? body,
    String? idempotencyKey,
  }) => _request('PATCH', path, body: body, idempotencyKey: idempotencyKey);

  Future<Map<String, dynamic>> delete(String path, {String? idempotencyKey}) =>
      _request('DELETE', path, idempotencyKey: idempotencyKey);

  /// Fetches protected image bytes (verification and receipt files) without
  /// exposing the bearer token in an image URL or a public cache key.
  Future<Uint8List> getBytes(String path) async {
    try {
      final session = await _sessionStore.read();
      final response = await _dio.get<List<int>>(
        path,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {
            if (session != null)
              'Authorization': 'Bearer ${session.accessToken}',
          },
        ),
      );
      if (response.statusCode == null || response.statusCode! >= 400) {
        throw const ApiException(
          message: 'تعذر تحميل الملف الخاص.',
          code: 'private_media_unavailable',
        );
      }
      return Uint8List.fromList(response.data ?? const <int>[]);
    } on ApiException {
      rethrow;
    } on DioException catch (_) {
      throw const ApiException(
        message: 'تعذر تحميل الملف الخاص. تحقق من اتصالك.',
        code: 'network_error',
      );
    }
  }

  Future<Map<String, dynamic>> postForm(
    String path, {
    required FormData body,
    String? idempotencyKey,
  }) => _request('POST', path, body: body, idempotencyKey: idempotencyKey);

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? body,
    String? idempotencyKey,
  }) async {
    try {
      final session = await _sessionStore.read();
      final headers = <String, dynamic>{
        if (session != null) 'Authorization': 'Bearer ${session.accessToken}',
        'Idempotency-Key': ?idempotencyKey,
      };
      final response = await _dio.request<dynamic>(
        path,
        data: body,
        queryParameters: query,
        options: Options(method: method, headers: headers),
      );
      final payload = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};
      if (response.statusCode == null ||
          response.statusCode! >= 400 ||
          payload['success'] != true) {
        final error = payload['error'] is Map
            ? Map<String, dynamic>.from(payload['error'] as Map)
            : const <String, dynamic>{};
        throw ApiException(
          message: (error['message'] as String?) ?? 'تعذر إكمال الطلب الآن.',
          code: error['code'] as String?,
          requestId: payload['request_id'] as String?,
          statusCode: response.statusCode,
        );
      }
      final data = payload['data'];
      return data is Map
          ? Map<String, dynamic>.from(data)
          : <String, dynamic>{};
    } on ApiException {
      rethrow;
    } on DioException catch (error) {
      throw ApiException(
        message:
            'تعذر الاتصال بالخادم. تحقق من اتصال الإنترنت ثم أعد المحاولة.',
        code: 'network_error',
        statusCode: error.response?.statusCode,
      );
    } on TimeoutException {
      throw const ApiException(
        message: 'انتهت مهلة الاتصال بالخادم.',
        code: 'timeout',
      );
    }
  }
}
