import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/api_client.dart';
import '../../../core/storage/secure_session.dart';

final class AuthRepository {
  AuthRepository(this._api, this._sessions);

  final ApiClient _api;
  final SecureSessionStore _sessions;

  Future<UserSession> login({
    required String phone,
    required String password,
  }) async {
    final data = await _api.post(
      '/auth/login',
      body: {'phone': phone.trim(), 'password': password},
    );
    return _savePayload(data);
  }

  Future<UserSession> register({
    required String fullName,
    required String username,
    required String phone,
    required String password,
    String role = 'customer',
  }) async {
    final data = await _api.post(
      '/auth/register',
      body: {
        'full_name': fullName.trim(),
        'username': username.trim(),
        'phone': phone.trim(),
        'password': password,
        'role': role,
      },
    );
    return _savePayload(data);
  }

  /// Registration-only availability endpoint. Final uniqueness is still enforced
  /// by the server at account creation time.
  Future<Map<String, dynamic>> availability({
    required String field,
    required String value,
  }) => _api.get('/auth/availability', query: {'field': field, 'value': value.trim()});

  Future<UserSession> refreshProfile() async {
    final data = await _api.get('/auth/me');
    final user = Map<String, dynamic>.from(data['user'] as Map? ?? const {});
    return _saveCurrentUser(user);
  }

  Future<UserSession> updateAvatar(XFile image) async {
    final uploaded = await _api.postForm(
      '/media',
      body: FormData.fromMap({
        'visibility': 'public',
        'file': await MultipartFile.fromFile(image.path, filename: image.name),
      }),
    );
    final media = Map<String, dynamic>.from(uploaded['media'] as Map? ?? const {});
    final mediaId = media['public_id'] as String?;
    if (mediaId == null || mediaId.isEmpty) {
      throw const FormatException('لم يعد الخادم معرفاً صالحاً للصورة المختارة.');
    }
    final updated = await _api.patch(
      '/auth/profile',
      body: {'avatar_media_id': mediaId},
    );
    return _saveCurrentUser(
      Map<String, dynamic>.from(updated['user'] as Map? ?? const {}),
    );
  }

  Future<UserSession> _saveCurrentUser(Map<String, dynamic> user) async {
    final current = await _sessions.read();
    if (current == null) {
      throw StateError('انتهت جلسة الحساب. سجّل الدخول ثم أعد المحاولة.');
    }
    final session = UserSession(accessToken: current.accessToken, user: user);
    await _sessions.save(session);
    return session;
  }

  Future<UserSession> _savePayload(Map<String, dynamic> data) async {
    final token = Map<String, dynamic>.from(data['token'] as Map? ?? const {});
    final user = Map<String, dynamic>.from(data['user'] as Map? ?? const {});
    final accessToken = token['access_token'] as String?;
    if (accessToken == null || accessToken.isEmpty) {
      throw const FormatException(
        'استجابة تسجيل الدخول لا تحتوي رمز وصول صالحاً.',
      );
    }
    final session = UserSession(accessToken: accessToken, user: user);
    await _sessions.save(session);
    return session;
  }

  Future<void> logout() async {
    try {
      await _api.post('/auth/logout');
    } finally {
      await _sessions.clear();
    }
  }
}
