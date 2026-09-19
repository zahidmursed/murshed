import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:flutter/foundation.dart';

/// স্ক্যানার শুরু/চলার সমস্যা — UI বাংলা বার্তা দেখাবে।
/// [fallbackToCamera] true হলে ক্যামেরা মোডে ফলব্যাক করা উচিত।
class ScannerException implements Exception {
  final String message;
  final bool fallbackToCamera;
  final String? code; // মূল exception code — ডায়াগনোস্টিক

  const ScannerException(this.message,
      {this.fallbackToCamera = false, this.code});

  @override
  String toString() => message;
}

/// স্ক্যানের ফল — JPEG পেজ-ফাইলগুলো + (চাইলে) স্ক্যানারের তৈরি PDF।
class ScanResultData {
  final List<String> images;
  final String? pdfPath;

  const ScanResultData({required this.images, this.pdfPath});

  bool get isEmpty => images.isEmpty && !(pdfPath?.isNotEmpty ?? false);
}

/// cunning_document_scanner-এর পাতলা র‍্যাপার।
/// Android-এ ML Kit থাকলে অটো এজ-ডিটেকশন+সোজা+ছায়ামুক্ত; Play Services
/// নেই এমন ডিভাইসে প্লাগইন নিজেই বিল্ট-ইন স্ক্যানারে ফলব্যাক করে —
/// এখানে শুধু অপশন, রিটার্ন-পাথ ও এরর-ম্যাপিং সামলানো হয়।
class ScannerService {
  ScannerService._();

  /// স্ক্যানার UI চালু করে; ফল [ScanResultData] হিসেবে ফেরত দেয়।
  /// [includePdf] true হলে স্ক্যানারের তৈরি PDF-ও পাওয়া যায় (FORM-এর জন্য)।
  /// ইউজার বাতিল করলে খালি ফল; সমস্যায় [ScannerException] ছোড়ে।
  static Future<ScanResultData> scanDocument(
      {int pageLimit = 5, bool includePdf = false}) async {
    try {
      final paths = await CunningDocumentScanner.getPictures(
        noOfPages: pageLimit,
        scannerSource: ScannerSource.cameraAndGallery,
        asPdf: includePdf,
      );
      final images = List<String>.from(paths ?? const <String>[]);
      if (images.isEmpty) {
        return const ScanResultData(images: []); // ইউজার বাতিল
      }
      // শেষ আইটেম PDF হলে (asPdf: true) আলাদা করে রাখা হয়
      String? pdfPath;
      if (includePdf && images.isNotEmpty) {
        final last = images.last.toLowerCase();
        if (last.endsWith('.pdf')) {
          pdfPath = images.removeLast();
        }
      }
      return ScanResultData(images: images, pdfPath: pdfPath);
    } on CunningDocumentScannerException catch (e) {
      debugPrint('Scanner error: ${e.code} ${e.message}');
      throw ScannerException(
        'স্ক্যানার চালু করা যায়নি — আবার চেষ্টা করুন',
        fallbackToCamera: true,
        code: e.code,
      );
    } catch (e) {
      debugPrint('Scanner error: $e');
      throw const ScannerException(
        'স্ক্যানার চালু করা যায়নি — আবার চেষ্টা করুন',
        fallbackToCamera: true,
      );
    }
  }

  /// cunning_document_scanner-এর অস্থায়ী স্ক্যান-ফাইল পরিষ্কার করে।
  static Future<void> cleanCache() async {
    try {
      await CunningDocumentScanner.cleanCache();
    } catch (e) {
      debugPrint('Scanner cleanCache failed: $e');
    }
  }
}