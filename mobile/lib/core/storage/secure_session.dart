import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final class UserSession {
  const UserSession({required this.accessToken, required this.user});

  final String accessToken;
  final Map<String, dynamic> user;

  List<String> get roles =>
      List<String>.from(user['roles'] as List? ?? const []);
  String get fullName =>
      (user['full_name'] as String?)?.trim() ?? 'مستخدم تجارتي';
  String? get username => user['username'] as String?;
  String? get phone => user['phone'] as String?;
  String? get identityLabel {
    final handle = username?.trim();
    final number = phone?.trim();
    if (handle != null && handle.isNotEmpty && number != null && number.isNotEmpty) return '@$handle · $number';
    if (handle != null && handle.isNotEmpty) return '@$handle';
    return number?.isEmpty == true ? null : number;
  }

  Map<String, dynamic> toJson() => {'access_token': accessToken, 'user': user};

  static UserSession? fromJson(String raw) {
    try {
      final value = jsonDecode(raw) as Map<String, dynamic>;
      final token = value['access_token'] as String?;
      final user = value['user'] as Map<String, dynamic>?;
      if (token == null || token.isEmpty || user == null) return null;
      return UserSession(accessToken: token, user: user);
    } catch (_) {
      return null;
    }
  }
}

/// Authentication credentials stay in encrypted platform storage, never SQLite.
final class SecureSessionStore {
  SecureSessionStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'tijarti.mobile.session.v1';
  final FlutterSecureStorage _storage;

  Future<UserSession?> read() async {
    final raw = await _storage.read(key: _key);
    return raw == null ? null : UserSession.fromJson(raw);
  }

  Future<void> save(UserSession session) =>
      _storage.write(key: _key, value: jsonEncode(session.toJson()));

  Future<void> clear() => _storage.delete(key: _key);
}
