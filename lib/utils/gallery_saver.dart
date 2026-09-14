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
  /// Native side URI (String) ফেরত দেয়। ব্যর্থ হলে false —
  /// অ্যাপ-ফোল্ডারের কপি নিরাপদ থাকে।
  static Future<bool> saveToGallery({
    required String filePath,
    required String fileName,
  }) async {
    try {
      final uri = await _channel.invokeMethod<String>('saveToGallery', {
        'path': filePath,
        'fileName': fileName,
        'album': album,
      });
      return uri != null && uri.isNotEmpty;
    } catch (e) {
      // PlatformException/TypeError — যেকোনো ব্যর্থতায় ক্যাপচার ফ্লো চলবে
      debugPrint('Gallery save failed: $e');
      return false;
    }
  }

  /// গ্যালারি থেকে এই দাখিলার ছবি মুছে দেয় (নিজের সেভ করা এন্ট্রি)।
  /// Native side মোছা এন্ট্রির সংখ্যা (int) ফেরত দেয় — exception না হলেই সফল।
  static Future<bool> deleteFromGallery({required String fileName}) async {
    try {
      await _channel.invokeMethod<dynamic>('deleteFromGallery', {
        'fileName': fileName,
        'album': album,
      });
      return true;
    } catch (e) {
      debugPrint('Gallery delete failed: $e');
      return false;
    }
  }

  /// গ্যালারির Pictures/DakhilaCamera-তে থাকা ফাইলনামগুলো (পুরনো ছবি রিকভারি)।
  /// PlatformException (PERMISSION_DENIED) propagate হয় — UI দেখাবে।
  static Future<List<String>> listGalleryPhotos() async {
    try {
      final names =
          await _channel.invokeMethod<List<dynamic>>('listGalleryPhotos');
      return names?.cast<String>() ?? const [];
    } on PlatformException {
      rethrow; // PERMISSION_DENIED — settings-এ দেখানো হয়
    } on MissingPluginException {
      debugPrint('GallerySaver: platform channel not available');
      return const [];
    }
  }

  /// গ্যালারির কপি থেকে অ্যাপ ডিরেক্টরিতে ফাইল ফেরত আনে (রিকভারি)।
  static Future<bool> copyGalleryPhoto({
    required String fileName,
    required String destPath,
  }) async {
    try {
      final ok = await _channel.invokeMethod<bool>('copyGalleryPhoto', {
        'fileName': fileName,
        'destPath': destPath,
      });
      return ok ?? false;
    } on PlatformException catch (e) {
      debugPrint('Gallery copy failed: ${e.code} ${e.message}');
      return false;
    } on MissingPluginException {
      debugPrint('GallerySaver: platform channel not available');
      return false;
    }
  }

  /// যেকোনো এক্সপোর্ট ফাইল (ZIP/PDF/CSV) সিস্টেম শেয়ার শিটে পাঠায়
  /// (native FileProvider intent — MainActivity.kt)।
  static Future<bool> shareFile({
    required String path,
    String mime = '*/*',
  }) async {
    try {
      final ok = await _channel.invokeMethod<bool>('shareFile', {
        'path': path,
        'mime': mime,
      });
      return ok ?? false;
    } on PlatformException catch (e) {
      debugPrint('Share file failed: ${e.code} ${e.message}');
      return false;
    } on MissingPluginException {
      debugPrint('GallerySaver: platform channel not available');
      return false;
    }
  }
}
