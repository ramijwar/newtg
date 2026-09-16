/// Build with a different endpoint when staging or production changes:
/// flutter run --dart-define=API_BASE_URL=https://example.com/s_api/api/v1
final class AppConfig {
  AppConfig._();

  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://t3lam.site/s_api/api/v1',
  );

  static const appName = 'تجارتي';
  static const requestTimeout = Duration(seconds: 20);

  static String mediaUrl(String publicId) => '$apiBaseUrl/media/$publicId';
}
