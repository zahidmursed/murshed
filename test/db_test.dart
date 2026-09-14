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
  });
}
