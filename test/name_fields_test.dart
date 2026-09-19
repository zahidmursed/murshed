import 'dart:io';

import 'package:dakhila_camera/db/database_helper.dart';
import 'package:dakhila_camera/models/student.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('copyWith carries and changes name En/Ar fields', () {
    final s = Student(
      dakhila: '281',
      stuName: 'মোঃ আব্দুল্লাহ',
      className: 'মিশকাত',
      forikNo: '1',
      fatherName: 'আব্দুর রহমান',
      dakhilaYear: '2026',
      imagePath: '/tmp/281.jpg',
      isCaptured: 1,
      totalDocs: 2,
    );

    // ডিফল্ট খালি
    expect(s.stuNameEn, '');
    expect(s.stuNameAr, '');

    final edited = s.copyWith(
      stuNameEn: 'Md. Abdullah',
      stuNameAr: 'محمد عبد الله',
      fatherNameEn: 'Abdur Rahman',
      fatherNameAr: 'عبد الرحمن',
      motherNameEn: 'Ayesha Begum',
      motherNameAr: 'عائشة بيغوم',
    );

    expect(edited.stuNameEn, 'Md. Abdullah');
    expect(edited.stuNameAr, 'محمد عبد الله');
    expect(edited.fatherNameEn, 'Abdur Rahman');
    expect(edited.fatherNameAr, 'عبد الرحمن');
    expect(edited.motherNameEn, 'Ayesha Begum');
    expect(edited.motherNameAr, 'عائشة بيغوم');
    // বাংলা নাম ও অন্য মান অক্ষত
    expect(edited.stuName, 'মোঃ আব্দুল্লাহ');
    expect(edited.fatherName, 'আব্দুর রহমান');
    expect(edited.imagePath, '/tmp/281.jpg');
    expect(edited.isCaptured, 1);
  });

  test('name En/Ar fields persist through updateStudentInfo', () async {
    final tmpDir =
        await Directory.systemTemp.createTemp('dakhila_names_test');
    addTearDown(() async {
      await DatabaseHelper.instance.resetForTest();
      if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
    });
    await databaseFactory.setDatabasesPath(tmpDir.path);

    await DatabaseHelper.instance.replaceAllStudents([
      const {
        'dakhila': '281',
        'stu_name': 'মোঃ আব্দুল্লাহ',
        'class_name': 'মিশকাত',
        'forik_no': '1',
        'father_name': 'আব্দুর রহমান',
        'dakhila_year': '2026',
      },
    ]);

    final s = (await DatabaseHelper.instance.getAllStudents())
        .firstWhere((s) => s.dakhila == '281');
    expect(s.stuNameEn, ''); // শুরুতে খালি

    final updated = s.copyWith(
      stuNameEn: 'Md. Abdullah',
      stuNameAr: 'محمد عبد الله',
      fatherNameAr: 'عبد الرحمن',
    );
    await DatabaseHelper.instance
        .updateStudentInfo(updated.dakhila, updated.toMap());

    final after =
        (await DatabaseHelper.instance.getAllStudents())
            .firstWhere((s) => s.dakhila == '281');
    expect(after.stuNameEn, 'Md. Abdullah');
    expect(after.stuNameAr, 'محمد عبد الله');
    expect(after.fatherNameAr, 'عبد الرحمن');
    // is_edited সেট হয়েছে — ইমপোর্ট-সংরক্ষণের মার্কার
    expect(after.totalDocs, 0);
  });

  test('name En/Ar survive replaceAllStudents even without is_edited',
      () async {
    final tmpDir =
        await Directory.systemTemp.createTemp('dakhila_names_import');
    addTearDown(() async {
      await DatabaseHelper.instance.resetForTest();
      if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
    });
    await databaseFactory.setDatabasesPath(tmpDir.path);

    await DatabaseHelper.instance.replaceAllStudents([
      const {
        'dakhila': '281',
        'stu_name': 'মোঃ আব্দুল্লাহ',
        'class_name': 'মিশকাত',
        'forik_no': '1',
        'father_name': 'আব্দুর রহমান',
        'dakhila_year': '2026',
      },
    ]);
    final s = (await DatabaseHelper.instance.getAllStudents())
        .firstWhere((s) => s.dakhila == '281');
    // সরাসরি ম্যাপ-আপডেট (updateStudentInfo পথ নয়) — তবু কলাম লেখা হয়
    await DatabaseHelper.instance
        .updateStudentInfo(s.dakhila, s.copyWith(stuNameEn: 'Md. Abdullah').toMap());

    // নতুন ইমপোর্ট — stu_name_en কী নেই, কিন্তু পুরনো মান টিকে থাকা চাই
    await DatabaseHelper.instance.replaceAllStudents([
      const {
        'dakhila': '281',
        'stu_name': 'মোঃ আব্দুল্লাহ',
        'class_name': 'মিশকাত',
        'forik_no': '1',
        'father_name': 'আব্দুর রহমান',
        'dakhila_year': '2026',
      },
    ]);

    final after =
        (await DatabaseHelper.instance.getAllStudents())
            .firstWhere((s) => s.dakhila == '281');
    expect(after.stuNameEn, 'Md. Abdullah');
  });
}
