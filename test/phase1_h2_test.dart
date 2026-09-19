import 'dart:io';

import 'package:dakhila_camera/db/database_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Phase 1 (H2) — ইমপোর্ট collision-গার্ড ও রিসেট-সিমেনটিকস টেস্ট।
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Map<String, dynamic> row(
    String dakhila, {
    String cls = 'দাখিলা ১ম',
    String forik = '1',
    String dYear = '2026',
    String eYear = '2026',
    String name = 'নাম',
  }) =>
      {
        'dakhila': dakhila,
        'stu_name': name,
        'class_name': cls,
        'forik_no': forik,
        'dakhila_year': dYear,
        'exam_year': eYear,
      };

  test('same year: capture, edits, names and documents preserved', () async {
    final tmpDir = await Directory.systemTemp.createTemp('dakhila_h2_test');
    addTearDown(() async {
      await DatabaseHelper.instance.resetForTest();
      if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
    });
    await databaseFactory.setDatabasesPath(tmpDir.path);

    final db = DatabaseHelper.instance;
    final r1 = await db.replaceAllStudents(
        [row('101'), row('102', forik: '2')]);
    expect(r1.imported, 2);
    expect(r1.collisions, isEmpty);

    await db.updateImage('101', '${tmpDir.path}/101.jpg');
    await db.updateImage('102', '${tmpDir.path}/102.jpg');
    await db.insertDocument('102', 'BIRTH', '${tmpDir.path}/102_birth.jpg');

    final r2 = await db.replaceAllStudents(
        [row('101'), row('102', forik: '2')]);
    expect(r2.imported, 2);
    expect(r2.collisions, isEmpty);

    final all = await db.getAllStudents();
    final s101 = all.firstWhere((s) => s.dakhila == '101');
    final s102 = all.firstWhere((s) => s.dakhila == '102');
    expect(s101.isCaptured, 1);
    expect(s101.imagePath, endsWith('101.jpg'));
    expect(s102.isCaptured, 1);
    // updateImage নিজেই PHOTO ডক-রো বসায় + BIRTH → totalDocs=2
    expect(s102.totalDocs, 2);
  });

  test('year mismatch: capture/document NOT carried to new person',
      () async {
    final tmpDir = await Directory.systemTemp.createTemp('dakhila_h2_test');
    addTearDown(() async {
      await DatabaseHelper.instance.resetForTest();
      if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
    });
    await databaseFactory.setDatabasesPath(tmpDir.path);

    final db = DatabaseHelper.instance;
    await db.replaceAllStudents([row('201', name: 'পুরনো ছাত্র')]);
    await db.updateImage('201', '${tmpDir.path}/201.jpg');
    await db.insertDocument('201', 'PHOTO', '${tmpDir.path}/201.jpg');

    // একই দাখিলা, কিন্তু ভিন্ন বছর = ভিন্ন ব্যক্তি
    final r = await db
        .replaceAllStudents([row('201', dYear: '2027', eYear: '2027', name: 'নতুন ছাত্র')]);
    expect(r.imported, 1);
    expect(r.collisions, contains('201'));

    final all = await db.getAllStudents();
    final s = all.firstWhere((x) => x.dakhila == '201');
    expect(s.isCaptured, 0, reason: 'নতুন ব্যক্তি পুরনো ছবি পায় না');
    expect(s.imagePath, isNull);
    expect(s.totalDocs, 0, reason: 'নতুন ব্যক্তির নামে ডক-স্লট বসে না');
  });

  test('deleteAllStudents clears documents too (reset semantics)', () async {
    final tmpDir = await Directory.systemTemp.createTemp('dakhila_h2_test');
    addTearDown(() async {
      await DatabaseHelper.instance.resetForTest();
      if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
    });
    await databaseFactory.setDatabasesPath(tmpDir.path);

    final db = DatabaseHelper.instance;
    await db.replaceAllStudents([row('301')]);
    await db.updateImage('301', '${tmpDir.path}/301.jpg');
    await db.insertDocument('301', 'FORM', '${tmpDir.path}/301_form.jpg');

    await db.deleteAllStudents();
    expect(await db.getAllStudents(), isEmpty);
    final docs = await db.getDocuments('301');
    expect(docs, isEmpty, reason: 'রিসেটে documents-ও খালি হয়');
  });
}
