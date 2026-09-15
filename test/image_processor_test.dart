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
}
