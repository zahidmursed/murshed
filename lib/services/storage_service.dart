import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path_provider/path_provider.dart';

import '../models/document.dart';

/// Phase 6: ছাত্র-প্রতি ফোল্ডার স্টোরেজ (v2 লেআউট)।
/// `<app-dir>/DakhilaCamera/v2/<ক্লাস>/Forik_<n>/<দাখিলা>/PHOTO/<দাখিলা>.jpg`
class StorageService {
  StorageService._();

  static String _sanitize(String name) =>
      name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();

  /// ডকুমেন্ট ফাইলের নাম শুধু দাখিলা নম্বর: 281.jpg.
  /// টাইপ আলাদা ফোল্ডারে থাকে, তাই একই নামের তিন ফাইলে সংঘর্ষ হয় না।
  static String fileName(String dakhila, String ext) =>
      '${_sanitize(dakhila)}.${ext.toLowerCase()}';

  static String documentFolderName(DocType type) => type.name;

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
    final studentFolder = await getStudentFolder(className, forik, dakhila);
    final folder =
        Directory('${studentFolder.path}/${documentFolderName(type)}');
    if (!await folder.exists()) await folder.create(recursive: true);
    return '${folder.path}/${fileName(dakhila, ext)}';
  }

  /// রিভিউ/ম্যানুয়াল ক্রপের জন্য মূল capture অস্থায়ীভাবে রাখা হয়।
  /// এটি final student document নয় এবং OS-এর temporary storage পরিষ্কার করতে পারে।
  static Future<String> temporaryCapturePath(String dakhila) async {
    final temp = await getTemporaryDirectory();
    final dir = Directory('${temp.path}/DakhilaCamera/raw');
    if (!await dir.exists()) await dir.create(recursive: true);
    // ফিক্স: ক্যাপচারের পরে অ্যাপ মাঝপথে বন্ধ হলে raw ফাইল জমতে থাকত —
    // ১ ঘণ্টার পুরনো ফাইল মুছে দেই (চলমান review/crop-এর ফাইল অক্ষত থাকে)।
    try {
      final cutoff = DateTime.now().subtract(const Duration(hours: 1));
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final stat = await entity.stat();
        if (stat.modified.isBefore(cutoff)) await entity.delete();
      }
    } catch (_) {}
    return '${dir.path}/${_sanitize(dakhila)}_${DateTime.now().millisecondsSinceEpoch}.jpg';
  }

  /// প্রতিষ্ঠানের লোগো branding ফোল্ডারে কপি করে (আগের লোগো মুছে)।
  /// রিটার্ন: নতুন পাথ (ব্যর্থ হলে null)।
  static Future<String?> saveLogo(String srcPath) async {
    try {
      final src = File(srcPath);
      if (!await src.exists()) return null;
      final appDir = await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
      final dir = Directory('${appDir.path}/DakhilaCamera/branding');
      if (!await dir.exists()) await dir.create(recursive: true);
      final ext =
          srcPath.contains('.') ? srcPath.split('.').last.toLowerCase() : 'png';
      final dest = '${dir.path}/logo.$ext';
      for (final old in ['logo.png', 'logo.jpg', 'logo.jpeg']) {
        final f = File('${dir.path}/$old');
        if (old != 'logo.$ext' && await f.exists()) await f.delete();
      }
      await src.copy(dest);
      return dest;
    } catch (e) {
      debugPrint('Logo save failed: $e');
      return null;
    }
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
