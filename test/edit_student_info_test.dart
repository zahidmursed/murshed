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

  test('copyWith changes only the editable (level-1) fields', () {
    final s = Student(
      dakhila: '281',
      stuName: 'রাসেল',
      className: 'মিশকাত',
      forikNo: '1',
      fatherName: 'আব্দুল',
      guardianMobile: '01922373258',
      dakhilaYear: '2026',
      marhala: 'ফযীলত',
      examYear: '2025',
      avgMonth: '90',
      avg1st: '87.63',
      avg2nd: '80',
      avgFinal: '',
      addressVill: 'গ্রাম',
      addressPo: 'ডাকঘর',
      addressPs: 'থানা',
      addressDist: 'জেলা',
      imagePath: '/tmp/281.jpg',
      isCaptured: 1,
      totalDocs: 2,
    );

    final edited = s.copyWith(
      stuName: 'রাসেল মাহমূদ',
      guardianMobile: '01711111111',
      addressVill: 'নতুন গ্রাম',
      avgFinal: '95',
    );

    // বদলেছে
    expect(edited.stuName, 'রাসেল মাহমূদ');
    expect(edited.guardianMobile, '01711111111');
    expect(edited.addressVill, 'নতুন গ্রাম');
    expect(edited.avgFinal, '95');
    // অপরিবর্তিত (স্তর ২ — দাখিলা/ক্লাস/ফরিক)
    expect(edited.dakhila, '281');
    expect(edited.className, 'মিশকাত');
    expect(edited.forikNo, '1');
    // অন্য মান অক্ষত
    expect(edited.fatherName, 'আব্দুল');
    expect(edited.avg1st, '87.63');
    expect(edited.addressDist, 'জেলা');
    expect(edited.imagePath, '/tmp/281.jpg');
    expect(edited.isCaptured, 1);
    expect(edited.totalDocs, 2);
  });

  test('updateStudentInfo persists edits and keeps other rows untouched',
      () async {
    final tmpDir =
        await Directory.systemTemp.createTemp('dakhila_edit_test');
    addTearDown(() async {
      await DatabaseHelper.instance.resetForTest();
      if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
    });
    await databaseFactory.setDatabasesPath(tmpDir.path);

    await DatabaseHelper.instance.replaceAllStudents([
      const {
        'dakhila': '281',
        'stu_name': 'রাসেল',
        'class_name': 'মিশকাত',
        'forik_no': '1',
        'father_name': 'আব্দুল',
        'dakhila_year': '2026',
      },
      const {
        'dakhila': '282',
        'stu_name': 'রহিম',
        'class_name': 'মিশকাত',
        'forik_no': '1',
        'father_name': 'করিম',
        'dakhila_year': '2026',
      },
    ]);

    final s281 =
        (await DatabaseHelper.instance.getAllStudents()) // মাস্টার তালিকা
            .firstWhere((s) => s.dakhila == '281');
    final updated = s281.copyWith(
      stuName: 'রাসেল মাহমূদ',
      guardianMobile: '01711000001', // UI-স্তরেই normalize হয়ে আসে
      addressVill: 'পূর্ব মির্জারচর',
      avg1st: '87.63',
    );
    await DatabaseHelper.instance
        .updateStudentInfo(updated.dakhila, updated.toMap());

    final all = await DatabaseHelper.instance.getAllStudents();
    final after = all.firstWhere((s) => s.dakhila == '281');
    expect(after.stuName, 'রাসেল মাহমূদ');
    expect(after.guardianMobile, '01711000001');
    expect(after.addressVill, 'পূর্ব মির্জারচর');
    expect(after.avg1st, '87.63');
    expect(after.className, 'মিশকাত');
    expect(after.forikNo, '1');

    // অন্য রেকর্ড অক্ষত
    final s282 = all.firstWhere((s) => s.dakhila == '282');
    expect(s282.stuName, 'রহিম');
    expect(s282.fatherName, 'করিম');
    expect(s282.guardianMobile, '');
  });
}
