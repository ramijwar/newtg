import '../../../core/network/api_client.dart';

final class AppNotification {
  const AppNotification({
    required this.publicId,
    required this.category,
    required this.title,
    required this.body,
    required this.readAt,
    required this.createdAt,
    this.entityType,
    this.entityPublicId,
  });

  final String publicId;
  final String category;
  final String title;
  final String body;
  final String? readAt;
  final String? createdAt;
  final String? entityType;
  final String? entityPublicId;
  bool get isRead => readAt != null;

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
    publicId: json['public_id'] as String? ?? '',
    category: json['category'] as String? ?? 'general',
    title: json['title'] as String? ?? 'تحديث جديد',
    body: json['body'] as String? ?? '',
    readAt: json['read_at'] as String?,
    createdAt: json['created_at'] as String?,
    entityType: json['entity_type'] as String?,
    entityPublicId: json['entity_public_id'] as String?,
  );
}

final class NotificationFeed {
  const NotificationFeed({required this.items, required this.unreadCount});
  final List<AppNotification> items;
  final int unreadCount;
}

final class NotificationPreference {
  const NotificationPreference({required this.category, required this.inAppEnabled, required this.pushEnabled});
  final String category;
  final bool inAppEnabled;
  final bool pushEnabled;

  factory NotificationPreference.fromJson(Map<String, dynamic> json) => NotificationPreference(
    category: json['category'] as String? ?? 'system',
    inAppEnabled: json['in_app_enabled'] == true,
    pushEnabled: json['push_enabled'] == true,
  );

  Map<String, dynamic> toJson() => {'category': category, 'in_app_enabled': inAppEnabled, 'push_enabled': pushEnabled};

  NotificationPreference copyWith({bool? inAppEnabled, bool? pushEnabled}) => NotificationPreference(category: category, inAppEnabled: inAppEnabled ?? this.inAppEnabled, pushEnabled: pushEnabled ?? this.pushEnabled);
}

final class NotificationRepository {
  NotificationRepository(this._api);
  final ApiClient _api;

  Future<NotificationFeed> load() async {
    final data = await _api.get('/notifications');
    final raw = data['items'];
    final items = (raw is List ? raw : const [])
        .whereType<Map>()
        .map((item) => AppNotification.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
    return NotificationFeed(
      items: items,
      unreadCount: (data['unread_count'] as num?)?.toInt() ?? 0,
    );
  }

  Future<List<NotificationPreference>> preferences() async {
    final data = await _api.get('/notifications/preferences');
    final raw = data['items'];
    return (raw is List ? raw : const [])
        .whereType<Map>()
        .map((item) => NotificationPreference.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  Future<void> updatePreferences(List<NotificationPreference> preferences) => _api.patch(
    '/notifications/preferences',
    body: {'preferences': preferences.map((item) => item.toJson()).toList(growable: false)},
  );

  Future<void> markRead(String publicId) =>
      _api.patch('/notifications/${Uri.encodeComponent(publicId)}/read');

  Future<void> markAllRead() => _api.post('/notifications/read-all');

  Future<String?> registerAndroidDevice(String token) async {
    final data = await _api.post(
      '/notifications/devices',
      body: {'fcm_token': token, 'platform': 'android'},
    );
    final deviceRaw = data['device'];
    final device = deviceRaw is Map
        ? Map<String, dynamic>.from(deviceRaw)
        : const <String, dynamic>{};
    return device['public_id'] as String?;
  }

  Future<void> removeDevice(String publicId) =>
      _api.delete('/notifications/devices/${Uri.encodeComponent(publicId)}');
}
