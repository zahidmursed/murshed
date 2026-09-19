import 'dart:io';

import 'package:dakhila_camera/db/database_helper.dart';
import 'package:dakhila_camera/providers/student_provider.dart';
import 'package:dakhila_camera/utils/name_transliterator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// ফেজ B: ব্যাচ নাম-অটো-ফিল (ক্যাশ → ডিকশনারি/নিয়ম) + বাল্ক DB লেখা।
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    final tmpDir = await Directory.systemTemp.createTemp('dakhila_batch_test');
    addTearDown(() async {
      await DatabaseHelper.instance.resetForTest();
      if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
    });
    await databaseFactory.setDatabasesPath(tmpDir.path);
  });

  test('batchAutoFillNames fills empty En/Ar, keeps existing, caches dict hits',
      () async {
    final db = DatabaseHelper.instance;
    await db.replaceAllStudents([
      const {
        'dakhila': '281',
        'stu_name': 'মোঃ আব্দুল্লাহ হোসেন', // ডিকশনারি-মিল (সব টোকেন)
        'class_name': 'মিশকাত',
        'forik_no': '1',
        'dakhila_year': '2026',
      },
      const {
        'dakhila': '282',
        'stu_name': 'জগদীশ চন্দ্র', // ডিকশনারিতে নেই → নিয়ম-ফলব্যাক
        'class_name': 'মিশকাত',
        'forik_no': '1',
        'dakhila_year': '2026',
      },
      const {
        'dakhila': '283',
        'stu_name': 'আয়শা খাতুন', // ডিকশনারি-মিল
        'stu_name_en': 'Custom Aysha', // বিদ্যমান En রক্ষা পাওয়া চাই
        'class_name': 'মিশকাত',
        'forik_no': '1',
        'dakhila_year': '2026',
      },
    ]);

    final provider = StudentProvider();
    await provider.load();

    final res = await provider.batchAutoFillNames();

    expect(res.filled, 3);

    final all = await db.getAllStudents();
    final s281 = all.firstWhere((s) => s.dakhila == '281');
    expect(s281.stuNameEn, 'Md. Abdullah Hossain');
    expect(s281.stuNameAr, 'محمد عبد الله حسين');
    expect(s281.stuName, 'মোঃ আব্দুল্লাহ হোসেন'); // বাংলা অক্ষত
    expect(s281.stuNameEn.isNotEmpty, isTrue);

    // 282: নিয়ম-ফলব্যাক — পড়া যায় এমন ল্যাটিন, কিন্তু ক্যাশে যায় না
    final s282 = all.firstWhere((s) => s.dakhila == '282');
    expect(s282.stuNameEn.toLowerCase(), contains('jagadish'));
    final cachedRule = await db
        .lookupNameCache(NameTransliterator.cacheKey('জগদীশ চন্দ্র'));
    expect(cachedRule, isNull);

    // 283: বিদ্যমান En রক্ষা + খালি Ar পূরণ
    final s283 = all.firstWhere((s) => s.dakhila == '283');
    expect(s283.stuNameEn, 'Custom Aysha');
    expect(s283.stuNameAr, isNotEmpty);

    // ডিকশনারি-মিল নাম ক্যাশে আছে
    final cached = await db
        .lookupNameCache(NameTransliterator.cacheKey('মোঃ আব্দুল্লাহ হোসেন'));
    expect(cached, isNotNull);
    expect(cached!.english, 'Md. Abdullah Hossain');

    // is_edited=1 — কাস্টম ইমপোর্টে এসব মান সংরক্ষিত থাকবে
    for (final s in all) {
      expect(s.stuNameEn.isNotEmpty || s.stuNameAr.isNotEmpty, isTrue);
    }
  });

  test('batchAutoFillNames repairs broken En/Ar (Bengali leak) but keeps valid',
      () async {
    final db = DatabaseHelper.instance;
    await db.replaceAllStudents([
      const {
        // পুরনো ইঞ্জিনের ভাঙা আউটপুট: En-এ বাংলা 'ই', Ar-এ পুরো বাংলা নাম
        'dakhila': '501',
        'stu_name': 'রাইয়ান',
        'stu_name_en': 'raই',
        'stu_name_ar': 'রাইয়ান',
        'class_name': 'মিশকাত',
        'forik_no': '1',
        'dakhila_year': '2026',
      },
      const {
        // ভালো মান — ব্যাচে ওভাররাইট হওয়া চাই না
        'dakhila': '502',
        'stu_name': 'আয়শা খাতুন',
        'stu_name_en': 'Custom Aysha',
        'stu_name_ar': 'عائشة',
        'class_name': 'মিশকাত',
        'forik_no': '1',
        'dakhila_year': '2026',
      },
    ]);

    final provider = StudentProvider();
    await provider.load();

    final res = await provider.batchAutoFillNames();

    expect(res.filled, 1);
    expect(res.repaired, 1);

    final all = await db.getAllStudents();
    final s501 = all.firstWhere((s) => s.dakhila == '501');
    // মেরামতের পরে En/Ar-এ বাংলা অক্ষর নেই
    expect(NameTransliterator.containsBengali(s501.stuNameEn), isFalse);
    expect(NameTransliterator.containsBengali(s501.stuNameAr), isFalse);
    expect(s501.stuNameEn.toLowerCase(), contains('rayan'));
    // 'রাইয়ান' এখন ডিকশনারিতে (টপ-unknown স্ক্যান থেকে যোগ) → 'ريان'।
    // আগের নিয়ম-ইঞ্জিন আউটপুট ('راييان') ছিল য়+মাত্রা অক্ষর-অনুসারে লেখা।
    expect(s501.stuNameAr, 'ريان');
    // 'ريان' শুরু হয় ري দিয়ে (র+ই-কার) — নিয়ম-ইঞ্জিনের পুরনো 'راييان' নয়।
    expect(s501.stuNameAr.startsWith('ري'), isTrue);

    // ভালো মান অক্ষত
    final s502 = all.firstWhere((s) => s.dakhila == '502');
    expect(s502.stuNameEn, 'Custom Aysha');
    expect(s502.stuNameAr, 'عائشة');
  });

  test('bulkSaveNameFields writes in one transaction with cache rows',
      () async {
    final db = DatabaseHelper.instance;
    await db.replaceAllStudents([
      const {
        'dakhila': '401',
        'stu_name': 'রাসেল',
        'class_name': 'মিশকাত',
        'forik_no': '1',
        'dakhila_year': '2026',
      },
    ]);

    final n = await db.bulkSaveNameFields([
      (dakhila: '401', en: 'Rasel', ar: 'راسل'),
    ], [
      (key: 'রাসেল', en: 'Rasel', ar: 'راسل'),
    ]);
    expect(n, 1);

    final s = (await db.getAllStudents()).firstWhere((s) => s.dakhila == '401');
    expect(s.stuNameEn, 'Rasel');
    expect(s.stuNameAr, 'راسل');
    final cached = await db.lookupNameCache('রাসেল');
    expect(cached!.english, 'Rasel');
  });
}
