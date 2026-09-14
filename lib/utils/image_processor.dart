import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// ছবির মাঝখান থেকে 3:4 অনুপাতে ক্রপ করে 600×800 (পাসপোর্ট সাইজ)-এ রিসাইজ করে।
/// Pure function — ইউনিট টেস্টযোগ্য।
img.Image processPassportImage(img.Image source) {
  // EXIF orientation থাকলে প্রয়োগ করা হয়
  final oriented = img.bakeOrientation(source);

  final int w = oriented.width;
  final int h = oriented.height;

  int targetW = w;
  int targetH = (targetW * 4 / 3).toInt();
  if (targetH > h) {
    targetH = h;
    targetW = (targetH * 3 / 4).toInt();
  }

  final int x = (w - targetW) ~/ 2;
  final int y = (h - targetH) ~/ 2;

  final cropped =
      img.copyCrop(oriented, x: x, y: y, width: targetW, height: targetH);
  return img.copyResize(cropped, width: 600, height: 800);
}

/// JPEG bytes → passport-processed JPEG bytes (ডিকোড ব্যর্থ/অবৈধ হলে null)।
Uint8List? processPassportBytes(Uint8List bytes) {
  // image প্যাকেজের কিছু decoder অবৈধ input-এ exception ছোড়ে — null চুক্তি রক্ষা করতে
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    return null;
  }
  if (decoded == null) return null;
  return img.encodeJpg(processPassportImage(decoded), quality: 90);
}

/// ভারী ডিকোড/ক্রপ/রিসাইজ/এনকোড কাজ main isolate-এর বাইরে চালায় (UI jank এড়াতে)।
Future<Uint8List?> processPassportInIsolate(Uint8List bytes) {
  return Isolate.run(() => processPassportBytes(bytes));
}
