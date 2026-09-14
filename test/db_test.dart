import 'dart:io';

import 'package:dakhila_camera/db/database_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('JSON import, filter, search and image update work end-to-end',
      () async {
    final tmpDir = await Directory.systemTemp.createTemp('dakhila_db_test');
    addTearDown(() async {
      await DatabaseHelper.instance.resetForTest();
      if (await tmpDir.exists()) {
        await tmpDir.delete(recursive: true);
      }
    });
    await databaseFactory.setDatabasesPath(tmpDir.path);

    // প্রথম রান: assets/Data_basic.json থেকে ইমপোর্ট হবে (isolate-এ ডিকোড)
    await DatabaseHelper.instance.importJsonIfEmpty();

    final all = await DatabaseHelper.instance.getAllStudents();
    expect(all.length, greaterThan(1000));

    // দ্বিতীয়বার চালালে পুনরায় ইমপোর্ট হয় না (count > 0)
    await DatabaseHelper.instance.importJsonIfEmpty();
    expect((await DatabaseHelper.instance.getAllStudents()).length, all.length);

    // ফরিক ফিল্টার
    final forik1 =
        await DatabaseHelper.instance.getAllStudents(forikFilter: '1');
    expect(forik1, isNotEmpty);
    expect(forik1.every((s) => s.forikNo == '1'), isTrue);

    // নাম দিয়ে সার্চ
    final byName = await DatabaseHelper.instance.search('রাসেল');
    expect(byName, isNotEmpty);

    // দাখিলা দিয়ে সার্চ
    final byDakhila = await DatabaseHelper.instance.search('281');
    expect(byDakhila.any((s) => s.dakhila == '281'), isTrue);

    // ছবি সেভ-এর পর DB আপডেট
    await DatabaseHelper.instance.updateImage('281', '${tmpDir.path}/281.jpg');
    final updated =
        await DatabaseHelper.instance.getAllStudents(forikFilter: '1');
    final s281 = updated.firstWhere((s) => s.dakhila == '281');
    expect(s281.isCaptured, 1);
    expect(s281.imagePath, endsWith('281.jpg'));

    // ক্যাপচার রিসেট (delete ফিচার)
    await DatabaseHelper.instance.clearImage('281');
    final cleared =
        await DatabaseHelper.instance.getAllStudents(forikFilter: '1');
    final s281b = cleared.firstWhere((s) => s.dakhila == '281');
    expect(s281b.isCaptured, 0);
    expect(s281b.imagePath, isNull);

    // ফরিক-ভিত্তিক স্ট্যাট
    final stats = await DatabaseHelper.instance.getForikStats();
    expect(stats, isNotEmpty);
    final forik1Count =
        (await DatabaseHelper.instance.getAllStudents(forikFilter: '1')).length;
    final stat1 = stats.firstWhere((st) => st.forik == '1');
    expect(stat1.total, forik1Count);
    expect(stat1.captured, 0);
    expect(stat1.remaining, stat1.total);

    // কাস্টম ইমপোর্ট: রিপ্লেস + ক্যাপচার প্রিজার্ভ
    await DatabaseHelper.instance.updateImage('281', '${tmpDir.path}/281.jpg');
    final customMaps = <Map<String, dynamic>>[
      {
        'dakhila': '281',
        'stu_name': 'নতুন শিক্ষার্থী',
        'class_name': 'তাহফীজ',
        'forik_no': '3',
        'father_name': 'অভিভাবক',
        'dakhila_year': '2026',
      },
      {
        'dakhila': '900001',
        'stu_name': 'কাস্টম রেকর্ড',
        'class_name': 'হিফজুল কুরআন',
        'forik_no': '1',
        'father_name': '',
        'dakhila_year': '2026',
      },
    ];
    final imported =
        await DatabaseHelper.instance.replaceAllStudents(customMaps);
    expect(imported, 2);
    final afterImport = await DatabaseHelper.instance.getAllStudents();
    expect(afterImport.length, 2);
    final preserved = afterImport.firstWhere((s) => s.dakhila == '281');
    expect(preserved.isCaptured, 1); // ক্যাপচার প্রিজার্ভ হয়েছে
    expect(preserved.imagePath, endsWith('281.jpg'));
    expect(preserved.className, 'তাহফীজ');

    // ক্লাস > ফরিক লিস্ট
    final classes = await DatabaseHelper.instance.getDistinctClasses();
    expect(classes, containsAll(<String>['তাহফীজ', 'হিফজুল কুরআন']));
    expect(
      await DatabaseHelper.instance.getForiksForClass(className: 'তাহফীজ'),
      ['3'],
    );

    // রিসেট → বান্ডেল ডেটা ফিরে আসে
    await DatabaseHelper.instance.deleteAllStudents();
    await DatabaseHelper.instance.importJsonIfEmpty();
    final restored = await DatabaseHelper.instance.getAllStudents();
    expect(restored.length, greaterThan(1000));
    expect(await DatabaseHelper.instance.getDistinctClasses(), isNotEmpty);
    final s281AfterReset = restored.firstWhere((s) => s.dakhila == '281');
    expect(s281AfterReset.isCaptured, 0);
  });
}
