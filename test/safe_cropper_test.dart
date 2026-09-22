import 'dart:async';
import 'dart:io';

import 'package:dakhila_camera/utils/safe_cropper.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_cropper/image_cropper.dart';

/// SafeCropper-এর রিগ্রেশন টেস্ট — image_cropper-এর নেটিভ দিকের
/// "Reply already submitted" ক্র্যাশ (request=69, cancel-এ ফেটে;
/// upstream issue #189) ও হারানো রিপ্লাই থেকে রক্ষার নিয়মগুলো ধরে।
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.hunghd.vn/image_cropper');

  Future<void> mock(Future<Object?>? Function(MethodCall) handler) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
  }

  // image_cropper-এর Dart-সাইড sourcePath-এর অস্তিত্ব assert করে —
  // তাই টেস্টে সত্যিকারের অস্থায়ী ফাইল লাগে।
  late Directory tempDir;
  late String sourcePath;

  setUp(() async {
    SafeCropper.debugReset();
    tempDir = await Directory.systemTemp.createTemp('safe_cropper_test');
    sourcePath = '${tempDir.path}${Platform.pathSeparator}src.jpg';
    await File(sourcePath).writeAsBytes(<int>[1, 2, 3], flush: true);
  });

  tearDown(() async {
    SafeCropper.debugReset();
    await mock((call) async => null);
    await tempDir.delete(recursive: true);
  });

  test('native path-রিপ্লাই CroppedFile হিসেবে বেরিয়ে আসে', () async {
    await mock((call) async => '${tempDir.path}/cropped.jpg');
    final crop = await SafeCropper.crop(
      () => ImageCropper().cropImage(sourcePath: sourcePath),
    );
    expect(crop?.path, '${tempDir.path}/cropped.jpg');
  });

  test('native null-রিপ্লাই = বাতিল (null)', () async {
    await mock((call) async => null);
    final crop = await SafeCropper.crop(
      () => ImageCropper().cropImage(sourcePath: sourcePath),
    );
    expect(crop, isNull);
  });

  test('একসাথে একটিই ক্রপ — দ্বিতীয় ডাক সঙ্গে সঙ্গে null', () async {
    final deferred = Completer<Object?>();
    await mock((call) => deferred.future);

    final first = SafeCropper.crop(
      () => ImageCropper().cropImage(sourcePath: sourcePath),
    );

    // প্রথম ক্রপ এখনো চালু — দ্বিতীয় ডাক null দেবে, চ্যানেলে নতুন কল যাবে না।
    final second = await SafeCropper.crop(
      () => ImageCropper().cropImage(sourcePath: sourcePath),
    );
    expect(second, isNull);

    deferred.complete('${tempDir.path}/first.jpg');
    expect((await first)?.path, '${tempDir.path}/first.jpg');

    // প্রথমটা শেষ — গার্ড খুলে গেছে, নতুন ক্রপ আবার চলে।
    await mock((call) async => '${tempDir.path}/second.jpg');
    final third = await SafeCropper.crop(
      () => ImageCropper().cropImage(sourcePath: sourcePath),
    );
    expect(third?.path, '${tempDir.path}/second.jpg');
  });

  test('নেটিভ রিপ্লাই না এলে টাইমআউটে বাতিল (null) — UI ঝুলে থাকে না', () async {
    await mock((call) => Completer<Object?>().future); // কখনোই উত্তর দেয় না
    final crop = await SafeCropper.crop(
      () => ImageCropper().cropImage(sourcePath: sourcePath),
      timeout: const Duration(milliseconds: 50),
    );
    expect(crop, isNull);
  });

  test('টাইমআউটের পরেও গার্ড খোলা থাকে — নতুন ক্রপ চলে', () async {
    await mock((call) => Completer<Object?>().future);
    await SafeCropper.crop(
      () => ImageCropper().cropImage(sourcePath: sourcePath),
      timeout: const Duration(milliseconds: 50),
    );

    await mock((call) async => '${tempDir.path}/next.jpg');
    final next = await SafeCropper.crop(
      () => ImageCropper().cropImage(sourcePath: sourcePath),
    );
    expect(next?.path, '${tempDir.path}/next.jpg');
  });

  test('PlatformException প্রপাগেট করে (caller-এর catch কাজ করে)', () async {
    await mock((call) async =>
        throw PlatformException(code: 'crop_error', message: 'boom'));
    await expectLater(
      SafeCropper.crop(
        () => ImageCropper().cropImage(sourcePath: sourcePath),
      ),
      throwsA(isA<PlatformException>()),
    );
  });
}