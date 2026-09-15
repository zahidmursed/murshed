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

/// স্ক্যানের ফল — JPEG পেজ-ফাইলগুলো + (চাইলে) গুগলের প্রসেসড PDF।
class ScanResultData {
  final List<String> images;
  final String? pdfPath;

  const ScanResultData({required this.images, this.pdfPath});

  bool get isEmpty => images.isEmpty && !(pdfPath?.isNotEmpty ?? false);
}

/// Google ML Kit Document Scanner-এর পাতলা র‍্যাপার।
/// এজ-ডিটেকশন, বাঁকা সোজা ও ছায়ামুক্তকরণ গুগলের নিজস্ব UI-ই করে দেয় —
/// এখানে শুধু অপশন, রিটার্ন-পাথ ও এরর-ম্যাপিং সামলানো হয়।
class ScannerService {
  ScannerService._();

  /// গুগলের স্ক্যানার UI চালু করে; ফল [ScanResultData] হিসেবে ফেরত দেয়।
  /// [includePdf] true হলে গুগলের প্রসেসড PDF-ও পাওয়া যায় (FORM-এর জন্য)।
  /// ইউজার বাতিল করলে খালি ফল; Play Services/মডিউল সমস্যায়
  /// [ScannerException] (fallbackToCamera = true) ছোড়ে।
  static Future<ScanResultData> scanDocument(
      {int pageLimit = 5, bool includePdf = false}) async {
    final options = DocumentScannerOptions(
      documentFormats: {
        DocumentFormat.jpeg,
        if (includePdf) DocumentFormat.pdf,
      },
      pageLimit: pageLimit,
      mode: ScannerMode.full,
      isGalleryImport: true,
    );
    final scanner = DocumentScanner(options: options);
    try {
      final result = await scanner.scanDocument();
      final images = result.images ?? const <String>[];
      final pdfPath = result.pdf?.uri;
      if (images.isEmpty && (pdfPath == null || pdfPath.isEmpty)) {
        return const ScanResultData(images: []); // ইউজার বাতিল
      }
      return ScanResultData(
        images: images,
        pdfPath: (pdfPath == null || pdfPath.isEmpty) ? null : pdfPath,
      );
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