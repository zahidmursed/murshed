import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// চূড়ান্ত পাসপোর্ট ছবির নির্ধারিত মাপ।
const int passportWidth = 431;
const int passportHeight = 531;

enum PassportPreset { natural, fresh, bright }

extension PassportPresetLabel on PassportPreset {
  String get label => switch (this) {
        PassportPreset.natural => 'Natural',
        PassportPreset.fresh => 'Fresh',
        PassportPreset.bright => 'Bright',
      };
}

/// ছবির মাঝখান থেকে 431:531 অনুপাতে ক্রপ করে, হালকা auto-enhancement-সহ
/// 431×531 পিক্সেলে রিসাইজ করে।
/// Pure function — ইউনিট টেস্টযোগ্য।
img.Image processPassportImage(
  img.Image source, {
  PassportPreset preset = PassportPreset.fresh,
  bool enhance = true,
}) {
  // EXIF orientation থাকলে প্রয়োগ করা হয়
  final oriented = img.bakeOrientation(source);

  final int w = oriented.width;
  final int h = oriented.height;

  int targetW = w;
  int targetH = (targetW * passportHeight / passportWidth).round();
  if (targetH > h) {
    targetH = h;
    targetW = (targetH * passportWidth / passportHeight).round();
  }

  final int x = (w - targetW) ~/ 2;
  final int y = (h - targetH) ~/ 2;

  final cropped =
      img.copyCrop(oriented, x: x, y: y, width: targetW, height: targetH);
  final resized =
      img.copyResize(cropped, width: passportWidth, height: passportHeight);
  return enhance ? _autoEnhance(resized, preset) : resized;
}

/// ছোট (431×531) ছবিতে চলে বলে দ্রুত। দৃশ্যটি অন্ধকার হলে একটু বেশি উজ্জ্বল
/// করে; এরপর হালকা contrast/saturation ও highlight lift দেয়—ত্বকের রং বদলে
/// যাওয়ার মতো aggressive beauty filter ব্যবহার করা হয় না।
img.Image _autoEnhance(img.Image image, PassportPreset preset) {
  var luminanceTotal = 0.0;
  var samples = 0;
  // প্রতি 4 পিক্সেলে sample নেওয়ায় average নির্ণয় খুব দ্রুত হয়।
  for (var y = 0; y < image.height; y += 4) {
    for (var x = 0; x < image.width; x += 4) {
      final p = image.getPixel(x, y);
      luminanceTotal += 0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b;
      samples++;
    }
  }
  final average = luminanceTotal / samples;
  final baseBrightness = average < 90
      ? 1.14
      : average < 130
          ? 1.08
          : average < 170
              ? 1.04
              : 1.0;
  final (brightnessBoost, contrast, saturation, highlightLift) =
      switch (preset) {
    PassportPreset.natural => (0.0, 1.02, 1.01, 0.0),
    PassportPreset.fresh => (0.0, 1.06, 1.06, 0.04),
    PassportPreset.bright => (0.06, 1.08, 1.05, 0.06),
  };
  final brightness = baseBrightness + brightnessBoost;

  int color(double value) => value.round().clamp(0, 255);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final p = image.getPixel(x, y);
      // খুব হালকা contrast-এর জন্য RGB channel প্রস্তুত।
      var r = ((p.r - 128) * contrast + 128) * brightness;
      var g = ((p.g - 128) * contrast + 128) * brightness;
      var b = ((p.b - 128) * contrast + 128) * brightness;
      final luma = 0.2126 * r + 0.7152 * g + 0.0722 * b;
      // 6% saturation: fresh দেখায়, কিন্তু অতিরঞ্জিত হয় না।
      r = luma + (r - luma) * saturation;
      g = luma + (g - luma) * saturation;
      b = luma + (b - luma) * saturation;
      // উজ্জ্বল অংশে সামান্য soft highlight lift = subtle glossy finish।
      if (luma > 155 && highlightLift > 0) {
        r += (255 - r) * highlightLift;
        g += (255 - g) * highlightLift;
        b += (255 - b) * highlightLift;
      }
      image.setPixelRgba(x, y, color(r), color(g), color(b), p.a.toInt());
    }
  }
  return image;
}

/// JPEG bytes → passport-processed JPEG bytes (ডিকোড ব্যর্থ/অবৈধ হলে null)।
Uint8List? processPassportBytes(
  Uint8List bytes, [
  PassportPreset preset = PassportPreset.fresh,
  bool enhance = true,
]) {
  // image প্যাকেজের কিছু decoder অবৈধ input-এ exception ছোড়ে — null চুক্তি রক্ষা করতে
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    return null;
  }
  if (decoded == null) return null;
  return img.encodeJpg(
    processPassportImage(decoded, preset: preset, enhance: enhance),
    quality: 92,
  );
}

/// ভারী ডিকোড/ক্রপ/রিসাইজ/এনকোড কাজ main isolate-এর বাইরে চালায় (UI jank এড়াতে)।
Future<Uint8List?> processPassportInIsolate(
  Uint8List bytes, [
  PassportPreset preset = PassportPreset.fresh,
  bool enhance = true,
]) {
  return Isolate.run(() => processPassportBytes(bytes, preset, enhance));
}

/// ছবির আলো ও sharpness-এর হালকা পরীক্ষা। 0=ঠিক, 1=অন্ধকার, 2=blur,
/// 3=দুটোই। এটি সতর্কতা মাত্র; ছবি সেভ বন্ধ করে না।
int assessPhotoQualityBytes(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return 0;
  final preview = img.copyResize(decoded, width: 160);
  var light = 0.0;
  var edges = 0.0;
  var count = 0;
  for (var y = 1; y < preview.height; y += 2) {
    for (var x = 1; x < preview.width; x += 2) {
      final p = preview.getPixel(x, y);
      final left = preview.getPixel(x - 1, y);
      final up = preview.getPixel(x, y - 1);
      final luma = 0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b;
      final leftLuma = 0.2126 * left.r + 0.7152 * left.g + 0.0722 * left.b;
      final upLuma = 0.2126 * up.r + 0.7152 * up.g + 0.0722 * up.b;
      light += luma;
      edges += (luma - leftLuma).abs() + (luma - upLuma).abs();
      count++;
    }
  }
  if (count == 0) return 0;
  final dark = light / count < 55;
  final blurry = edges / count < 12;
  return (dark ? 1 : 0) | (blurry ? 2 : 0);
}

Future<int> assessPhotoQualityInIsolate(Uint8List bytes) =>
    Isolate.run(() => assessPhotoQualityBytes(bytes));

/// ছবিকে aspect-ratio ধরে রেখে সর্বোচ্চ [maxSide] পিক্সেলে রিসাইজ — isolate-এ।
/// আগে থেকেই ছোট হলে অপরিবর্তিত ছবি JPEG (quality 92) হিসেবে ফেরত দেয়।
/// ডিকোড ব্যর্থ হলে null।
Future<Uint8List?> resizeImageInIsolate(Uint8List bytes,
    {required int maxSide}) {
  return Isolate.run(() {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    // PNG সোর্স হলে PNG-ই ফেরত — এক্সটেনশন ও কনটেন্ট মিলবে
    final isPng = bytes.length > 8 && bytes[0] == 0x89 && bytes[1] == 0x50;
    final int w = decoded.width;
    final int h = decoded.height;
    final img.Image out;
    if (w <= maxSide && h <= maxSide) {
      out = decoded;
    } else {
      final double ratio = w >= h ? maxSide / w : maxSide / h;
      out = img.copyResize(decoded,
          width: (w * ratio).round(), height: (h * ratio).round());
    }
    return isPng ? img.encodePng(out) : img.encodeJpg(out, quality: 92);
  });
}

/// নেটিভ ক্রপ-এডিটরে (uCrop) দেওয়ার আগে সোর্স প্রস্তুত করে:
/// খুব বড় ছবি হলে সর্বোচ্চ [maxSide] বাহুতে নামিয়ে [destPath] (ASCII-নিরাপদ
/// অস্থায়ী ফাইল) এ JPEG লেখে — OOM ও ইউনিকোড-পাথ ক্র্যাশ এড়াতে।
/// রিটার্ন: destPath (ডিকোড ব্যর্থ হলে null)।
Future<String?> prepareCropSource({
  required String srcPath,
  required String destPath,
  int maxSide = 3000,
}) {
  return Isolate.run(() async {
    final bytes = await File(srcPath).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final int w = decoded.width;
    final int h = decoded.height;
    final img.Image out;
    if (w > maxSide || h > maxSide) {
      final double ratio = w >= h ? maxSide / w : maxSide / h;
      out = img.copyResize(decoded,
          width: (w * ratio).round(), height: (h * ratio).round());
    } else {
      out = decoded;
    }
    await File(destPath)
        .writeAsBytes(img.encodeJpg(out, quality: 95), flush: true);
    return destPath;
  });
}
