import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One persisted policy used by every app image picker before upload.
/// Native image_picker compression happens locally, so original camera files
/// are not sent unnecessarily when the device/platform supports it.
final class ImageUploadPolicy {
  ImageUploadPolicy._();

  static const _qualityKey = 'image_upload_quality';
  static const _widthKey = 'image_upload_max_width';
  static int _quality = 85;
  static int _maxWidth = 1800;

  static int get quality => _quality;
  static int get maxWidth => _maxWidth;

  static Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    _quality = preferences.getInt(_qualityKey) ?? _quality;
    _maxWidth = preferences.getInt(_widthKey) ?? _maxWidth;
  }

  static Future<void> update({required int quality, required int maxWidth}) async {
    _quality = quality.clamp(35, 100).toInt();
    _maxWidth = maxWidth.clamp(720, 3000).toInt();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_qualityKey, _quality);
    await preferences.setInt(_widthKey, _maxWidth);
  }

  static Future<XFile?> pick(ImageSource source) => ImagePicker().pickImage(
    source: source,
    imageQuality: _quality,
    maxWidth: _maxWidth.toDouble(),
  );
}
