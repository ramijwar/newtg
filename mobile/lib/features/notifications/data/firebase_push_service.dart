import 'dart:async';

import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notification_repository.dart';

/// A safe, API-only navigation target sent in FCM data. It never carries a
/// message body, account identifier, or access token.
enum PushPermissionState { unavailable, needsRequest, granted, denied }

/// Separates Android permission from the server-side association of this FCM token.
enum PushDeviceRegistrationState { unavailable, notRegistered, registering, registered, failed }

final class NotificationTarget {
  const NotificationTarget({
    this.notificationId,
    this.category,
    this.entityType,
    this.entityPublicId,
  });

  final String? notificationId;
  final String? category;
  final String? entityType;
  final String? entityPublicId;

  factory NotificationTarget.fromRemoteMessage(RemoteMessage message) =>
      NotificationTarget.fromData(message.data);

  factory NotificationTarget.fromData(Map<String, dynamic> data) {
    String? value(String key) {
      final raw = data[key]?.toString().trim();
      return raw == null || raw.isEmpty ? null : raw;
    }
    return NotificationTarget(
      notificationId: value('notification_id'),
      category: value('category'),
      entityType: value('entity_type'),
      entityPublicId: value('entity_public_id'),
    );
  }
}

/// Registers only the FCM registration token. Firebase credentials never enter
/// the application source; Android receives its public configuration from
/// google-services.json and the server reads its service account from a secret.
final class FirebasePushService {
  FirebasePushService(
    this._repository, {
    required bool isFirebaseAvailable,
  }) : _isFirebaseAvailable = isFirebaseAvailable;

  final NotificationRepository _repository;
  final bool _isFirebaseAvailable;
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  static const AndroidNotificationChannel _androidChannel = AndroidNotificationChannel(
    'tijarti_updates', 'تحديثات تجارتي',
    description: 'تحديثات الطلبات والحراج والمتاجر والدعم.',
    importance: Importance.high,
  );
  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;
  String? _deviceId;
  bool _checkedInitialMessage = false;
  PushPermissionState _permissionState = PushPermissionState.needsRequest;
  PushDeviceRegistrationState _registrationState = PushDeviceRegistrationState.notRegistered;
  bool _localNotificationsReady = false;

  PushPermissionState get permissionState => _permissionState;
  PushDeviceRegistrationState get registrationState => _registrationState;

  /// Refreshes the in-app count while the app is open.
  void Function()? onForegroundNotification;

  /// Lets the UI open the related API-backed screen after the user taps a push.
  void Function(NotificationTarget target)? onNotificationOpened;

  /// Enables a visible, user-controlled Android permission prompt instead of
  /// silently presenting it during sign-in.
  void Function(PushPermissionState state)? onPermissionStateChanged;
  void Function(PushDeviceRegistrationState state)? onRegistrationStateChanged;

  void _setRegistrationState(PushDeviceRegistrationState state) {
    if (_registrationState == state) return;
    _registrationState = state;
    onRegistrationStateChanged?.call(state);
  }

  void _setPermissionState(PushPermissionState state) {
    if (_permissionState == state) return;
    _permissionState = state;
    onPermissionStateChanged?.call(state);
  }

  PushPermissionState _fromSettings(NotificationSettings settings) => switch (settings.authorizationStatus) {
    AuthorizationStatus.authorized || AuthorizationStatus.provisional => PushPermissionState.granted,
    AuthorizationStatus.denied => PushPermissionState.denied,
    _ => PushPermissionState.needsRequest,
  };

  Future<PushPermissionState> refreshPermissionState() async {
    if (!_isFirebaseAvailable) {
      _setPermissionState(PushPermissionState.unavailable);
      return _permissionState;
    }
    try {
      _setPermissionState(_fromSettings(await _messaging.getNotificationSettings()));
    } catch (_) {
      _setPermissionState(PushPermissionState.unavailable);
      _setRegistrationState(PushDeviceRegistrationState.unavailable);
      return _permissionState;
    }
    if (_permissionState == PushPermissionState.granted) {
      await _registerCurrentToken();
    } else {
      _setRegistrationState(PushDeviceRegistrationState.notRegistered);
    }
    return _permissionState;
  }

  Future<PushPermissionState> requestPermission() async {
    if (!_isFirebaseAvailable) {
      _setPermissionState(PushPermissionState.unavailable);
      return _permissionState;
    }
    try {
      final settings = await _messaging.requestPermission(alert: true, badge: true, sound: true);
      _setPermissionState(_fromSettings(settings));
    } catch (_) {
      _setPermissionState(PushPermissionState.unavailable);
      _setRegistrationState(PushDeviceRegistrationState.unavailable);
      return _permissionState;
    }
    if (_permissionState == PushPermissionState.granted) {
      await _registerCurrentToken();
    } else {
      _setRegistrationState(PushDeviceRegistrationState.notRegistered);
    }
    return _permissionState;
  }

  Future<void> activate() async {
    if (!_isFirebaseAvailable) { _setPermissionState(PushPermissionState.unavailable); _setRegistrationState(PushDeviceRegistrationState.unavailable); return; }
    try {
      await _initializeLocalNotifications();
      _foregroundSubscription ??= FirebaseMessaging.onMessage.listen((message) {
        unawaited(_showForegroundNotification(message));
        onForegroundNotification?.call();
      });
      _openedSubscription ??= FirebaseMessaging.onMessageOpenedApp.listen(_handleOpenedMessage);
      _tokenSubscription ??= _messaging.onTokenRefresh.listen(_registerToken);
      final permission = await refreshPermissionState();
      // Product policy: request again on every app launch until Android grants it.
      // Android may eventually require the user to change the setting manually;
      // requestPermission still safely returns the current denied state then.
      if (permission != PushPermissionState.granted && permission != PushPermissionState.unavailable) {
        await requestPermission();
      }
      // getInitialMessage is non-null only when Android launched the app from a tap.
      if (!_checkedInitialMessage) {
        _checkedInitialMessage = true;
        final initial = await _messaging.getInitialMessage();
        if (initial != null) _handleOpenedMessage(initial);
      }
    } catch (_) {
      _setPermissionState(PushPermissionState.unavailable);
      _setRegistrationState(PushDeviceRegistrationState.unavailable);
    }
  }

  Future<void> _initializeLocalNotifications() async {
    if (_localNotificationsReady) return;
    const settings = InitializationSettings(android: AndroidInitializationSettings('ic_stat_tijarti'));
    await _localNotifications.initialize(settings, onDidReceiveNotificationResponse: (response) {
      _handleLocalPayload(response.payload);
    });
    // A foreground local notification can outlive a terminated process. Restore
    // its safe navigation target on the next app launch as well.
    final launch = await _localNotifications.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) {
      _handleLocalPayload(launch?.notificationResponse?.payload);
    }
    final android = _localNotifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(_androidChannel);
    _localNotificationsReady = true;
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    if (!_localNotificationsReady) return;
    final notification = message.notification;
    final messageTitle = notification?.title;
    final messageBody = notification?.body;
    final title = messageTitle != null && messageTitle.trim().isNotEmpty ? messageTitle : 'تحديث من تجارتي';
    final body = messageBody != null && messageBody.trim().isNotEmpty ? messageBody : 'لديك إشعار جديد.';
    final safePayload = <String, dynamic>{
      for (final key in ['notification_id', 'category', 'entity_type', 'entity_public_id'])
        if (message.data[key]?.toString().trim().isNotEmpty == true) key: message.data[key].toString(),
    };
    await _localNotifications.show(
      message.messageId?.hashCode ?? DateTime.now().microsecondsSinceEpoch.remainder(1 << 31),
      title, body,
      const NotificationDetails(android: AndroidNotificationDetails(
        'tijarti_updates', 'تحديثات تجارتي',
        channelDescription: 'تحديثات الطلبات والحراج والمتاجر والدعم.',
        importance: Importance.high, priority: Priority.high,
        icon: 'ic_stat_tijarti',
      )),
      payload: jsonEncode(safePayload),
    );
  }

  void _handleLocalPayload(String? raw) {
    if (raw == null || raw.isEmpty) return;
    try {
      final data = jsonDecode(raw);
      if (data is Map) _handleLocalTarget(Map<String, dynamic>.from(data));
    } catch (_) {
      // A malformed local payload cannot navigate the user anywhere.
    }
  }

  void _handleLocalTarget(Map<String, dynamic> data) => onNotificationOpened?.call(NotificationTarget.fromData(data));

  Future<void> _registerCurrentToken() async {
    final token = await _messaging.getToken();
    if (token != null && token.isNotEmpty) await _registerToken(token);
  }

  Future<void> deactivate() async {
    try {
      if (_deviceId != null) await _repository.removeDevice(_deviceId!);
    } catch (_) {
      // The token will be re-associated with the next authenticated session.
    } finally {
      _deviceId = null;
      _setRegistrationState(PushDeviceRegistrationState.notRegistered);
      await _tokenSubscription?.cancel();
      await _foregroundSubscription?.cancel();
      await _openedSubscription?.cancel();
      _tokenSubscription = null;
      _foregroundSubscription = null;
      _openedSubscription = null;
    }
  }

  void _handleOpenedMessage(RemoteMessage message) {
    onNotificationOpened?.call(NotificationTarget.fromRemoteMessage(message));
  }

  Future<void> _registerToken(String token) async {
    _setRegistrationState(PushDeviceRegistrationState.registering);
    try {
      final deviceId = await _repository.registerAndroidDevice(token);
      if (deviceId == null || deviceId.isEmpty) throw StateError('missing_device_id');
      _deviceId = deviceId;
      _setRegistrationState(PushDeviceRegistrationState.registered);
    } catch (_) {
      // Permission can be granted while the server is offline. Keep this state
      // explicit so the user can retry by reopening the notifications screen.
      _setRegistrationState(PushDeviceRegistrationState.failed);
    }
  }
}
