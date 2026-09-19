import 'dart:io';

import 'package:dakhila_camera/db/database_helper.dart';
import 'package:dakhila_camera/models/teacher.dart';
import 'package:dakhila_camera/services/teacher_directory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('teachers table seeded from bundled xlsx (fresh install)', () async {
    final tmpDir = await Directory.systemTemp.createTemp('dakhila_teacher_db');
    addTearDown(() async {
      await DatabaseHelper.instance.resetForTest();
      if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
    });
    await databaseFactory.setDatabasesPath(tmpDir.path);

    // প্রথম openDatabase → onCreate → teachers টেবিল + bundled xlsx সিড
    final teachers = await DatabaseHelper.instance.getTeachers();
    expect(teachers, isNotEmpty);
    // বান্ডেল এক্সেলে ১২৫ রো — সব এসেছে কিনা
    expect(teachers.length, 125);
    // ক্লাস-লেভেল (ফরিক-উদাসীন) এন্ট্রি ম্যাচ করে
    final ifta = TeacherDirectory.find(teachers, 'ইফতা', '');
    expect(ifta, isNotNull);
    expect(ifta!.mobile, isNotEmpty);
  });

  test('upsert/edit/delete teacher works with natural key (class+forik)',
      () async {
    final tmpDir = await Directory.systemTemp.createTemp('dakhila_teacher_db2');
    addTearDown(() async {
      await DatabaseHelper.instance.resetForTest();
      if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
    });
    await databaseFactory.setDatabasesPath(tmpDir.path);
    await DatabaseHelper.instance.getTeachers(); // টেবিল + সিড নিশ্চিত

    // নতুন যোগ
    final ok = await DatabaseHelper.instance.upsertTeacher(const TeacherInfo(
      className: 'টেস্ট ক্লাস',
      forik: '9',
      nameBn: 'মাওঃ টেস্ট',
      nameEn: 'Test Teacher',
      mobile: '01711000000',
    ));
    expect(ok, isTrue);

    var teachers = await DatabaseHelper.instance.getTeachers();
    final found = TeacherDirectory.find(teachers, 'টেস্ট ক্লাস', '9');
    expect(found, isNotNull);
    expect(found!.nameBn, 'মাওঃ টেস্ট');

    // সম্পাদনা (একই key → replace)
    await DatabaseHelper.instance.upsertTeacher(const TeacherInfo(
      className: 'টেস্ট ক্লাস',
      forik: '9',
      nameBn: 'মাওঃ টেস্ট উদ্ধৃত',
      nameEn: '',
      mobile: '01811000000',
    ));
    teachers = await DatabaseHelper.instance.getTeachers();
    final edited = TeacherDirectory.find(teachers, 'টেস্ট ক্লাস', '9');
    expect(edited!.nameBn, 'মাওঃ টেস্ট উদ্ধৃত');
    // একই key — ডুপ্লিকেট রো নেই
    expect(teachers.where((t) => t.className == 'টেস্ট ক্লাস').length, 1);

    // মুছে ফেলা
    final deleted =
        await DatabaseHelper.instance.deleteTeacher('টেস্ট ক্লাস', '9');
    expect(deleted, 1);
    teachers = await DatabaseHelper.instance.getTeachers();
    expect(TeacherDirectory.find(teachers, 'টেস্ট ক্লাস', '9'), isNull);

    // বান্ডেল সিড অক্ষত
    expect(TeacherDirectory.find(teachers, 'ইফতা', ''), isNotNull);
  });

  test('restoreTeacherSeed wipes edits and refills from bundled xlsx',
      () async {
    final tmpDir = await Directory.systemTemp.createTemp('dakhila_teacher_db3');
    addTearDown(() async {
      await DatabaseHelper.instance.resetForTest();
      if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
    });
    await databaseFactory.setDatabasesPath(tmpDir.path);
    await DatabaseHelper.instance.getTeachers();

    await DatabaseHelper.instance.upsertTeacher(const TeacherInfo(
      className: 'অস্থায়ী ক্লাস',
      forik: '',
      nameBn: 'মাওঃ অস্থায়ী',
      nameEn: '',
      mobile: '',
    ));

    final count = await DatabaseHelper.instance.restoreTeacherSeed();
    expect(count, 125);

    final teachers = await DatabaseHelper.instance.getTeachers();
    expect(teachers.length, 125);
    expect(TeacherDirectory.find(teachers, 'অস্থায়ী ক্লাস', ''), isNull);
  });

  test('teacher list sorts by class level (শিক্ষা-ক্রম), unknown class last',
      () async {
    final tmpDir =
        await Directory.systemTemp.createTemp('dakhila_teacher_order');
    addTearDown(() async {
      await DatabaseHelper.instance.resetForTest();
      if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
    });
    await databaseFactory.setDatabasesPath(tmpDir.path);
    await DatabaseHelper.instance.getTeachers(); // টেবিল + bundled সিড

    // ছাত্র-ডেটা: ইফতা=লেভেল ১, তাকমিল=লেভেল ১০; 'মিযান' — ছাত্রই নেই
    await DatabaseHelper.instance.replaceAllStudents([
      {
        'dakhila': '701',
        'stu_name': 'ক',
        'class_name': 'ইফতা',
        'forik_no': '1',
        'class_level': '1',
        'dakhila_year': '2026',
      },
      {
        'dakhila': '702',
        'stu_name': 'খ',
        'class_name': 'তাকমিল',
        'forik_no': '1',
        'class_level': '10',
        'dakhila_year': '2026',
      },
    ]);

    // শিক্ষক নাম-ক্রমে দিলে হতো [তাকমিল, মিযান, ইফতা] — লেভেলে হবে [ইফতা, তাকমিল, মিযান]
    await DatabaseHelper.instance.upsertTeacher(const TeacherInfo(
      className: 'তাকমিল',
      forik: '',
      nameBn: 'শিক্ষক তাকমিল',
      nameEn: '',
      mobile: '',
    ));
    await DatabaseHelper.instance.upsertTeacher(const TeacherInfo(
      className: 'মিযান',
      forik: '',
      nameBn: 'শিক্ষক মিযান',
      nameEn: '',
      mobile: '',
    ));
    await DatabaseHelper.instance.upsertTeacher(const TeacherInfo(
      className: 'ইফতা',
      forik: '',
      nameBn: 'শিক্ষক ইফতা',
      nameEn: '',
      mobile: '',
    ));

    final teachers = await DatabaseHelper.instance.getTeachers();
    final order = teachers.map((t) => t.className).toList();
    // বান্ডেল সিডের অন্য ক্লাসগুলোও থাকে; তাকমিল/মিযান-এর একাধিক ফরিক-রোও —
    // তাই প্রথম উপস্থিতির ক্রমেই আমার তিনটার লেভেল-ক্রম যাচাই করি
    final seen = <String>{};
    final filtered = <String>[];
    for (final c in order) {
      if (const ['ইফতা', 'তাকমিল', 'মিযান'].contains(c) && !seen.contains(c)) {
        seen.add(c);
        filtered.add(c);
      }
    }
    expect(filtered, ['ইফতা', 'তাকমিল', 'মিযান']);
  });
}
