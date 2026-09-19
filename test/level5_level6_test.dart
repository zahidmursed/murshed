import 'dart:io';

import 'package:dakhila_camera/db/database_helper.dart';
import 'package:dakhila_camera/models/student.dart';
import 'package:dakhila_camera/providers/student_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('level 5: mother/birth fields flow through model and DB', () async {
    final tmpDir = await Directory.systemTemp.createTemp('lvl5_db');
    addTearDown(() async {
      await DatabaseHelper.instance.resetForTest();
      if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
    });
    await databaseFactory.setDatabasesPath(tmpDir.path);

    await DatabaseHelper.instance.replaceAllStudents([
      {
        'dakhila': '501',
        'stu_name': 'সালিম',
        'class_name': 'ইফতা',
        'mother_name': 'রাহিমা',
        'birth_date': '10-02-2001',
        'birth_certificate_no': '20015525703007910',
        'dakhila_year': '2026',
      },
    ]);

    final s = await DatabaseHelper.instance.getStudentByDakhila('501');
    expect(s!.motherName, 'রাহিমা');
    expect(s.birthDate, '10-02-2001');
    expect(s.birthCertNo, '20015525703007910');

    // copyWith + toMap রাউন্ড-ট্রিপ
    final edited = s.copyWith(motherName: 'নতুন মা', birthDate: '01-01-2002');
    final map = edited.toMap();
    expect(map['mother_name'], 'নতুন মা');
    expect(map['birth_date'], '01-01-2002');
    final reparsed = Student.fromJson({
      'MOTHER_NAME': map['mother_name'],
      'BIRTH_DATE': map['birth_date'],
    });
    expect(reparsed.motherName, 'নতুন মা');
  });

  test('level 5: bundled JSON backfills mother/birth on fresh import',
      () async {
    final tmpDir = await Directory.systemTemp.createTemp('lvl5_db2');
    addTearDown(() async {
      await DatabaseHelper.instance.resetForTest();
      if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
    });
    await databaseFactory.setDatabasesPath(tmpDir.path);

    await DatabaseHelper.instance.importJsonIfEmpty();
    final s = await DatabaseHelper.instance.getStudentByDakhila('281');
    expect(s, isNotNull);
    expect(s!.motherName, 'রাহিমা');
    expect(s.birthDate, '13-07-2003');
    expect(s.birthCertNo, '20035418713106228');
  });

  test('level 6: import preserves edited record (fields + class/forik)',
      () async {
    final tmpDir = await Directory.systemTemp.createTemp('lvl6_db');
    addTearDown(() async {
      await DatabaseHelper.instance.resetForTest();
      if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
    });
    await databaseFactory.setDatabasesPath(tmpDir.path);

    await DatabaseHelper.instance.replaceAllStudents([
      {
        'dakhila': '281',
        'stu_name': 'রাসেল',
        'class_name': 'পুরনো ক্লাস',
        'forik_no': '1',
        'dakhila_year': '2026',
      },
      {
        'dakhila': '282',
        'stu_name': 'রহিম',
        'class_name': 'পুরনো ক্লাস',
        'forik_no': '1',
        'dakhila_year': '2026',
      },
    ]);

    // অ্যাপে 281 সম্পাদনা: নাম+মোবাইল (স্তর ১) এবং ক্লাস/ফরিক (স্তর ২)
    final provider = StudentProvider();
    await provider.load();
    final s281 =
        await DatabaseHelper.instance.getStudentByDakhila('281');
    final edited = s281!.copyWith(
      stuName: 'রাসেল এডিট',
      guardianMobile: '01711111111',
      className: 'সরানো ক্লাস',
      forikNo: '9',
    );
    final r = await provider.editStudentIdentity(edited);
    expect(r.ok, isTrue);

    // নতুন ইমপোর্ট: 281-এ সম্পূর্ণ ভিন্ন ডেটা, 282-এ নতুন নাম
    final imported = await DatabaseHelper.instance.replaceAllStudents([
      {
        'dakhila': '281',
        'stu_name': 'ইমপোর্ট নাম',
        'class_name': 'পুরনো ক্লাস',
        'forik_no': '1',
        'guardian_mobile': '01900000000',
        'dakhila_year': '2026',
      },
      {
        'dakhila': '282',
        'stu_name': 'রহিম নতুন',
        'class_name': 'পুরনো ক্লাস',
        'forik_no': '2',
        'dakhila_year': '2026',
      },
    ]);
    expect(imported.imported, 2);

    // সম্পাদিত রেকর্ডের সম্পাদনা টিকে আছে (ইমপোর্টের মান জিতে যায়নি)
    final after281 =
        await DatabaseHelper.instance.getStudentByDakhila('281');
    expect(after281!.stuName, 'রাসেল এডিট');
    expect(after281.guardianMobile, '01711111111');
    expect(after281.className, 'সরানো ক্লাস');
    expect(after281.forikNo, '9');

    // অসম্পাদিত রেকর্ড ইমপোর্টের ডেটা নেয়
    final after282 =
        await DatabaseHelper.instance.getStudentByDakhila('282');
    expect(after282!.stuName, 'রহিম নতুন');
    expect(after282.forikNo, '2');
  });
}
