import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';

/// স্ক্যানার শুরু/চলার সমস্যা — UI বাংলা বার্তা দেখাবে।
/// [fallbackToCamera] true হলে ক্যামেরা মোডে ফলব্যাক করা উচিত
/// (Play Services/স্ক্যানার-মডিউল ডিভাইসে নেই)।
class ScannerException implements Exception {
  final String message;
  final bool fallbackToCamera;

  const ScannerException(this.message, {this.fallbackToCamera = false});

  @override
  String toString() => message;
}

/// Google ML Kit Document Scanner-এর পাতলা র‍্যাপার।
/// এজ-ডিটেকশন, বাঁকা সোজা ও ছায়ামুক্তকরণ গুগলের নিজস্ব UI-ই করে দেয় —
/// এখানে শুধু অপশন, রিটার্ন-পাথ ও এরর-ম্যাপিং সামলানো হয়।
class ScannerService {
  ScannerService._();

  /// গুগলের স্ক্যানার UI চালু করে; স্ক্যান শেষে JPEG পেজ-ফাইলের পাথ ফেরত দেয়।
  /// ইউজার বাতিল করলে খালি লিস্ট; Play Services/মডিউল সমস্যায়
  /// [ScannerException] (fallbackToCamera = true) ছোড়ে।
  static Future<List<String>> scanDocument({int pageLimit = 5}) async {
    final options = DocumentScannerOptions(
      documentFormats: const {DocumentFormat.jpeg},
      pageLimit: pageLimit,
      mode: ScannerMode.full,
      isGalleryImport: true,
    );
    final scanner = DocumentScanner(options: options);
    try {
      final result = await scanner.scanDocument();
      final images = result.images ?? const <String>[];
      if (images.isEmpty) return const <String>[]; // ইউজার বাতিল
      return images;
    } on PlatformException catch (e) {
      debugPrint('Scanner error: ${e.code} ${e.message}');
      throw const ScannerException(
        'স্ক্যানার চালু করা যায়নি — Google Play Services দরকার',
        fallbackToCamera: true,
      );
    } on MissingPluginException catch (e) {
      debugPrint('Scanner missing plugin: $e');
      throw const ScannerException(
        'স্ক্যানার চালু করা যায়নি — Google Play Services দরকার',
        fallbackToCamera: true,
      );
    } finally {
      try {
        await scanner.close();
      } catch (_) {}
    }
  }
}