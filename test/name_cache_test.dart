import 'dart:io';

import 'package:dakhila_camera/db/database_helper.dart';
import 'package:dakhila_camera/utils/name_transliterator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    final tmpDir = await Directory.systemTemp.createTemp('dakhila_cache_test');
    addTearDown(() async {
      await DatabaseHelper.instance.resetForTest();
      if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
    });
    await databaseFactory.setDatabasesPath(tmpDir.path);
  });

  test('cacheKey: abbreviation variants collapse to one key', () {
    expect(
      NameTransliterator.cacheKey('মোঃ আব্দুল্লাহ হোসেন'),
      NameTransliterator.cacheKey('মো: আব্দুল্লাহ হোসেন'),
    );
    expect(
      NameTransliterator.cacheKey('মোঃআব্দুল্লাহ'),
      NameTransliterator.cacheKey('মোঃ আব্দুল্লাহ'),
    );
    // সংক্ষেপের বাইরে ভিন্ন নাম → ভিন্ন কী
    expect(
      NameTransliterator.cacheKey('আব্দুল্লাহ') !=
          NameTransliterator.cacheKey('মোঃ আব্দুল্লাহ'),
      isTrue,
    );
  });

  test('save + lookup roundtrip', () async {
    final db = DatabaseHelper.instance;
    final key = NameTransliterator.cacheKey('মোঃ আব্দুল্লাহ হোসেন');
    final before = await db.lookupNameCache(key);
    expect(before, isNull); // শুরুতে খালি

    await db.saveNameCache(key, 'Md. Abdullah Hosen', 'محمد عبد الله حسين');
    final hit = await db.lookupNameCache(key);
    expect(hit, isNotNull);
    expect(hit!.english, 'Md. Abdullah Hosen');
    expect(hit.arabic, 'محمد عبد الله حسين');
  });

  test('lookup matches across abbreviation variants (normalized key)', () async {
    final db = DatabaseHelper.instance;
    // ইউজার একবার "মোঃ আব্দুল্লাহ" নিশ্চিত করেছে
    await db.saveNameCache(
      NameTransliterator.cacheKey('মোঃ আব্দুল্লাহ'),
      'Md. Abdullah',
      'محمد عبد الله',
    );
    // পরেরবার DB-তে "মো: আব্দুল্লাহ" বা "মোঃআব্দুল্লাহ" হলেও ম্যাচ করে
    final hit = await db
        .lookupNameCache(NameTransliterator.cacheKey('মো: আব্দুল্লাহ'));
    expect(hit, isNotNull);
    expect(hit!.english, 'Md. Abdullah');
    final hit2 = await db
        .lookupNameCache(NameTransliterator.cacheKey('মোঃআব্দুল্লাহ'));
    expect(hit2!.arabic, 'محمد عبد الله');
  });

  test('save replaces previous value for the same key', () async {
    final db = DatabaseHelper.instance;
    final key = NameTransliterator.cacheKey('রাসেল');
    await db.saveNameCache(key, 'Rasel', 'راسل');
    await db.saveNameCache(key, 'Rassel', 'راسيل');
    final hit = await db.lookupNameCache(key);
    expect(hit!.english, 'Rassel');
    expect(hit.arabic, 'راسيل');
  });
}
