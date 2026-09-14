import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// ছবি ফোনের গ্যালারিতে (Pictures/DakhilaCamera) সেভ/ডিলিট —
/// native MediaStore ব্যবহার করে (android/.../MainActivity.kt)।
/// Android 10+ এ নিজের সেভ করা ফাইলে কোনো permission লাগে না;
/// Android 9-এ WRITE_EXTERNAL_STORAGE (best-effort)।
class GallerySaver {
  static const MethodChannel _channel = MethodChannel('dakhila_camera/gallery');
  static const String album = 'DakhilaCamera';

  /// ছবিটি গ্যালারিতে সেভ/আপডেট করে (একই নামের আগের এন্ট্রি replace হয়)।
  /// ব্যর্থ হলে false — অ্যাপ-ফোল্ডারের কপি নিরাপদ থাকে।
  static Future<bool> saveToGallery({
    required String filePath,
    required String fileName,
  }) async {
    try {
      final ok = await _channel.invokeMethod<bool>('saveToGallery', {
        'path': filePath,
        'fileName': fileName,
        'album': album,
      });
      return ok ?? false;
    } on PlatformException catch (e) {
      debugPrint('Gallery save failed: ${e.code} ${e.message}');
      return false;
    } on MissingPluginException {
      debugPrint('GallerySaver: platform channel not available');
      return false;
    }
  }

  /// গ্যালারি থেকে এই দাখিলার ছবি মুছে দেয় (নিজের সেভ করা এন্ট্রি)।
  static Future<bool> deleteFromGallery({required String fileName}) async {
    try {
      final ok = await _channel.invokeMethod<bool>('deleteFromGallery', {
        'fileName': fileName,
        'album': album,
      });
      return ok ?? false;
    } on PlatformException catch (e) {
      debugPrint('Gallery delete failed: ${e.code} ${e.message}');
      return false;
    } on MissingPluginException {
      debugPrint('GallerySaver: platform channel not available');
      return false;
    }
  }
}
