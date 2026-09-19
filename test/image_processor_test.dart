import 'dart:typed_data';

import 'package:dakhila_camera/utils/image_processor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  group('processPassportImage', () {
    test('landscape source: center-crops to 431:531 then resizes correctly',
        () {
      final src = img.Image(width: 400, height: 400);
      img.fill(src, color: img.ColorRgb8(0, 255, 0)); // সবুজ
      // বাম পাশে 50px লাল ব্যান্ড — সঠিক ক্রপে (x=50 থেকে) এটি বাদ যাবে
      img.fillRect(src,
          x1: 0, y1: 0, x2: 49, y2: 399, color: img.ColorRgb8(255, 0, 0));

      final out = processPassportImage(src);

      expect(out.width, passportWidth);
      expect(out.height, passportHeight);

      // output x=20 → source col ≈ 60 → সবুজ হওয়া উচিত;
      // ক্রপ না হলে (squish) source col ≈ 13 → লাল হতো
      final px = out.getPixel(20, 400);
      expect(px.g, greaterThan(px.r));
    });

    test('already 431:531 portrait source needs no crop', () {
      final src = img.Image(width: 431, height: 531);
      img.fill(src, color: img.ColorRgb8(0, 0, 255)); // নীল

      final out = processPassportImage(src);

      expect(out.width, passportWidth);
      expect(out.height, passportHeight);
      final px = out.getPixel(300, 400);
      expect(px.b, greaterThan(px.r));
      expect(px.b, greaterThan(px.g));
    });

    test('enhancement can be disabled without changing the pixel values', () {
      final src = img.Image(width: 431, height: 531);
      img.fill(src, color: img.ColorRgb8(80, 120, 160));

      final out = processPassportImage(src, enhance: false);

      final px = out.getPixel(200, 200);
      expect(px.r, 80);
      expect(px.g, 120);
      expect(px.b, 160);
    });
  });

  group('processPassportBytes', () {
    test('returns decodable jpeg bytes with passport size', () {
      final src = img.Image(width: 800, height: 600);
      img.fill(src, color: img.ColorRgb8(128, 128, 128));
      final bytes = img.encodeJpg(src, quality: 90);

      final out = processPassportBytes(bytes);

      expect(out, isNotNull);
      expect(out!.lengthInBytes, greaterThan(0));
      final decoded = img.decodeJpg(out);
      expect(decoded, isNotNull);
      expect(decoded!.width, passportWidth);
      expect(decoded.height, passportHeight);
    });

    test('returns null for invalid image bytes', () {
      expect(processPassportBytes(Uint8List.fromList([1, 2, 3, 4])), isNull);
    });
  });

  group('document scanner helpers', () {
    img.Image solid(int w, int h, int r, int g, int b) {
      final im = img.Image(width: w, height: h);
      img.fill(im, color: img.ColorRgb8(r, g, b));
      return im;
    }

    test('mergePagesVerticallyInIsolate stacks pages (width preserved)',
        () async {
      final p1 = Uint8List.fromList(img.encodeJpg(solid(40, 20, 200, 0, 0)));
      final p2 = Uint8List.fromList(img.encodeJpg(solid(40, 10, 0, 0, 200)));
      final out = await mergePagesVerticallyInIsolate([p1, p2]);
      expect(out, isNotNull);
      final decoded = img.decodeImage(out!);
      expect(decoded, isNotNull);
      expect(decoded!.width, 40);
      expect(decoded.height, 30);
      // উপরে লাল, নিচে নীল
      final top = decoded.getPixel(20, 5);
      expect(top.r, greaterThan(top.b));
      final bottom = decoded.getPixel(20, 25);
      expect(bottom.b, greaterThan(bottom.r));
    });

    test('enhanceDocument gray makes channels equal', () async {
      final src = Uint8List.fromList(img.encodeJpg(solid(60, 40, 40, 160, 220)));
      final out =
          await enhanceDocumentInIsolate(src, DocumentFilterMode.gray);
      expect(out, isNotNull);
      final decoded = img.decodeImage(out!);
      final px = decoded!.getPixel(30, 20);
      expect((px.r - px.g).abs(), lessThan(30));
      expect((px.g - px.b).abs(), lessThan(30));
    });

    test('enhanceDocument bw collapses to dark text / bright paper', () async {
      final page = img.Image(width: 60, height: 40);
      img.fill(page, color: img.ColorRgb8(240, 240, 240));
      img.fillRect(
          page, x1: 0, y1: 0, x2: 59, y2: 19, color: img.ColorRgb8(30, 30, 30));
      final src = Uint8List.fromList(img.encodeJpg(page));
      final out = await enhanceDocumentInIsolate(src, DocumentFilterMode.bw);
      expect(out, isNotNull);
      final decoded = img.decodeImage(out!);
      final bright = decoded!.getPixel(30, 35).luminance;
      final dark = decoded.getPixel(30, 5).luminance;
      expect(bright, greaterThan(180));
      expect(dark, lessThan(100));
    });

    test('enhanceDocument magic brightens the bright regions', () async {
      final page = img.Image(width: 60, height: 40);
      img.fill(page, color: img.ColorRgb8(40, 40, 40));
      img.fillRect(
          page, x1: 0, y1: 0, x2: 59, y2: 19, color: img.ColorRgb8(90, 90, 90));
      final src = Uint8List.fromList(img.encodeJpg(page));
      final inLuma = img.decodeImage(src)!.getPixel(30, 5).luminance;
      final out = await enhanceDocumentInIsolate(src, DocumentFilterMode.magic);
      final decoded = img.decodeImage(out!);
      final outLuma = decoded!.getPixel(30, 5).luminance;
      expect(outLuma, greaterThan(inLuma + 100));
    });

    test('bw keeps text dark inside shadow (adaptive threshold)', () async {
      final page = img.Image(width: 200, height: 100);
      img.fill(page, color: img.ColorRgb8(240, 240, 240));
      // নিচের অর্ধেকে ছায়া (ধূসর কাগজ)
      img.fillRect(page, x1: 0, y1: 50, x2: 199, y2: 99,
          color: img.ColorRgb8(180, 180, 180));
      // উপরে ও নিচে — দুই জায়গাতেই লেখার দাগ
      img.fillRect(page, x1: 20, y1: 10, x2: 21, y2: 40,
          color: img.ColorRgb8(40, 40, 40));
      img.fillRect(page, x1: 20, y1: 60, x2: 21, y2: 90,
          color: img.ColorRgb8(40, 40, 40));
      final src = Uint8List.fromList(img.encodeJpg(page));
      final out = await enhanceDocumentInIsolate(src, DocumentFilterMode.bw);
      expect(out, isNotNull);
      final d = img.decodeImage(out!)!;
      // লেখা — ছায়ার ভিতরে-বাইরে দুই জায়গাতেই কালো
      expect(d.getPixel(20, 25).luminance, lessThan(100));
      expect(d.getPixel(20, 75).luminance, lessThan(100));
      // কাগজ — উজ্জ্বল ও ছায়ামাখা — দুটোই সাদা
      expect(d.getPixel(150, 25).luminance, greaterThan(180));
      expect(d.getPixel(150, 75).luminance, greaterThan(180));
    });

    test('magic evens out shadow gradient (illumination division)', () async {
      final page = img.Image(width: 200, height: 100);
      // বাম উজ্জ্বল (200) → ডান ছায়ামাখা (120) গ্রেডিয়েন্ট
      for (var x = 0; x < 200; x++) {
        final v = (200 - x * 80 ~/ 199).clamp(0, 255);
        img.drawLine(page, x1: x, y1: 0, x2: x, y2: 99,
            color: img.ColorRgb8(v, v, v));
      }
      final src = Uint8List.fromList(img.encodeJpg(page));
      final out = await enhanceDocumentInIsolate(src, DocumentFilterMode.magic);
      expect(out, isNotNull);
      final d = img.decodeImage(out!)!;
      // উজ্জ্বল ও ছায়ামাখা — দুই পাশই কাগজের মতো সাদা হওয়া চাই
      expect(d.getPixel(30, 50).luminance, greaterThan(220));
      expect(d.getPixel(170, 50).luminance, greaterThan(220));
    });

    test('limitLongSideInIsolate caps the long side', () async {
      final src = Uint8List.fromList(img.encodeJpg(solid(800, 400, 10, 200, 10)));
      final out = await limitLongSideInIsolate(src, maxSide: 400);
      expect(out, isNotNull);
      final decoded = img.decodeImage(out!);
      expect(decoded!.width, 400);
      expect(decoded.height, 200);
    });
  });
}
