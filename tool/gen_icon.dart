// লঞ্চার আইকনের সোর্স তৈরি করে (jamiaP.png থেকে):
//   assets/icon.png            → 1024×1024 (teal ব্যাকগ্রাউন্ড, লোগো 92%)
//   assets/icon_foreground.png → 1024×1024 transparent (লোগো 66% — adaptive safe zone)
// চালানোর নিয়ম: dart run tool/gen_icon.dart
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:image/image.dart' as img;

void main() {
  final src = img.decodePng(File('jamiaP.png').readAsBytesSync());
  if (src == null) {
    stderr.writeln('jamiaP.png decode failed');
    exit(1);
  }
  print('source: ${src.width}x${src.height}');

  // ১) মূল আইকন: স্কয়ার ক্যানভাস (teal) + লোগো ৯২%
  final mainCanvas = img.Image(width: 1024, height: 1024);
  img.fill(mainCanvas, color: img.ColorRgb8(0, 137, 123)); // teal #00897B
  final mainLogo = _fit(src, (1024 * 0.92).round());
  img.compositeImage(
    mainCanvas,
    mainLogo,
    dstX: (1024 - mainLogo.width) ~/ 2,
    dstY: (1024 - mainLogo.height) ~/ 2,
  );
  File('assets/icon.png').writeAsBytesSync(img.encodePng(mainCanvas, level: 6));

  // ২) Adaptive foreground: transparent ক্যানভাস + লোগো ৬৬% (safe zone)
  final fgCanvas = img.Image(width: 1024, height: 1024);
  final fgLogo = _fit(src, (1024 * 0.66).round());
  img.compositeImage(
    fgCanvas,
    fgLogo,
    dstX: (1024 - fgLogo.width) ~/ 2,
    dstY: (1024 - fgLogo.height) ~/ 2,
  );
  File('assets/icon_foreground.png')
      .writeAsBytesSync(img.encodePng(fgCanvas, level: 6));

  print('assets/icon.png + assets/icon_foreground.png generated');
}

img.Image _fit(img.Image src, int target) {
  final ratio = src.width / src.height;
  final int w;
  final int h;
  if (ratio >= 1) {
    w = target;
    h = (target / ratio).round();
  } else {
    h = target;
    w = (target * ratio).round();
  }
  return img.copyResize(src, width: w, height: h);
}
