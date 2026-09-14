import 'package:dakhila_camera/utils/gallery_saver.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression: native side যা টাইপের রিপ্লাই দেয় ঠিক সেটাই পড়তে হবে
/// (আগে saveToGallery String রিপ্লাইকে bool-এ cast করার চেষ্টায় ভেঙে যেত)।
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dakhila_camera/gallery');

  Future<void> mock(Future<Object?>? Function(MethodCall) handler) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
  }

  tearDown(() async {
    await mock((call) async => null);
  });

  test('saveToGallery accepts native String reply (regression)', () async {
    await mock((call) async => 'content://media/external/images/media/1');
    final ok = await GallerySaver.saveToGallery(
      filePath: '/x/281.jpg',
      fileName: '281.jpg',
    );
    expect(ok, isTrue);
  });

  test('saveToGallery returns false when native returns null', () async {
    await mock((call) async => null);
    final ok = await GallerySaver.saveToGallery(
      filePath: '/x/281.jpg',
      fileName: '281.jpg',
    );
    expect(ok, isFalse);
  });

  test('saveToGallery returns false on PlatformException', () async {
    await mock((call) async =>
        throw PlatformException(code: 'SAVE_FAILED', message: 'boom'));
    final ok = await GallerySaver.saveToGallery(
      filePath: '/x/281.jpg',
      fileName: '281.jpg',
    );
    expect(ok, isFalse);
  });

  test('deleteFromGallery accepts native int reply', () async {
    await mock((call) async => 2); // মোছা এন্ট্রির সংখ্যা
    final ok = await GallerySaver.deleteFromGallery(fileName: '281.jpg');
    expect(ok, isTrue);
  });

  test('copyGalleryPhoto and shareFile pass bool replies through', () async {
    await mock((call) async => true);
    expect(
      await GallerySaver.copyGalleryPhoto(
          fileName: '281.jpg', destPath: '/d/281.jpg'),
      isTrue,
    );
    expect(await GallerySaver.shareFile(path: '/e/export.zip'), isTrue);
  });

  test('listGalleryPhotos returns names and rethrows PlatformException',
      () async {
    await mock((call) async => <String>['281.jpg', '282.jpg']);
    expect(await GallerySaver.listGalleryPhotos(), ['281.jpg', '282.jpg']);

    await mock(
        (call) async => throw PlatformException(code: 'PERMISSION_DENIED'));
    await expectLater(
      GallerySaver.listGalleryPhotos(),
      throwsA(isA<PlatformException>()),
    );
  });
}
