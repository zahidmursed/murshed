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
