import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/document.dart';

/// Phase 6: ছাত্র-প্রতি ফোল্ডার স্টোরেজ (v2 লেআউট)।
/// `<app-dir>/DakhilaCamera/v2/<ক্লাস>/Forik_<n>/<দাখিলা>/<দাখিলা>_PHOTO.jpg`
class StorageService {
  StorageService._();

  static String _sanitize(String name) =>
      name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();

  /// ডকুমেন্ট ফাইলের নাম: 281_PHOTO.jpg
  static String fileName(String dakhila, DocType type, String ext) =>
      '${dakhila}_${type.name}.${ext.toLowerCase()}';

  /// ছাত্রের ফোল্ডার (অ্যাপ ডিরেক্টরির ভিতরে) — না থাকলে তৈরি করে।
  static Future<Directory> getStudentFolder(
      String className, String forik, String dakhila) async {
    final appDir = await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    final dir = Directory([
      appDir.path,
      'DakhilaCamera',
      'v2',
      _sanitize(className.isEmpty ? 'Unknown' : className),
      'Forik_${_sanitize(forik.isEmpty ? '0' : forik)}',
      _sanitize(dakhila),
    ].join('/'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// ডকুমেন্ট ফাইলের পূর্ণ পাথ (ফোল্ডার তৈরি করে)।
  static Future<String> documentPath(String className, String forik,
      String dakhila, DocType type, String ext) async {
    final folder = await getStudentFolder(className, forik, dakhila);
    return '${folder.path}/${fileName(dakhila, type, ext)}';
  }

  /// পুরনো flat লেআউট থেকে ফাইল নতুন v2 ফোল্ডারে **কপি** করে
  /// (পুরনো ফাইল অক্ষত থাকে — DB আপডেট সফল হলে caller মুছবে)।
  /// রিটার্ন: নতুন পাথ (ব্যর্থ হলে null)।
  static Future<String?> copyToStudentFolder({
    required String className,
    required String forik,
    required String dakhila,
    required DocType type,
    required String oldPath,
  }) async {
    try {
      final src = File(oldPath);
      if (!await src.exists()) return null;
      final ext =
          oldPath.contains('.') ? oldPath.split('.').last.toLowerCase() : 'jpg';
      final newPath = await documentPath(className, forik, dakhila, type, ext);
      await src.copy(newPath);
      return newPath;
    } catch (_) {
      return null;
    }
  }
}
