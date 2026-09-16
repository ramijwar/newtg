import 'dart:io';

import 'package:flutter/services.dart';

/// Opens this application's notification page in Android system settings.
/// A platform channel keeps this one Android-specific action out of UI code
/// and avoids treating a rejected OS permission as an app preference.
final class AndroidNotificationSettings {
  static const _channel = MethodChannel('tijarti/android_notification_settings');

  static Future<bool> open() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('openNotificationSettings') ?? false;
    } on PlatformException {
      return false;
    }
  }
}
