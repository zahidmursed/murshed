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

  test('class dropdown follows numeric CLASS_LEVEL, not class name', () async {
    final dir = await Directory.systemTemp.createTemp('dakhila_class_level');
    addTearDown(() async {
      await DatabaseHelper.instance.resetForTest();
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    await databaseFactory.setDatabasesPath(dir.path);
    await DatabaseHelper.instance.replaceAllStudents([
      {
        'dakhila': '3',
        'stu_name': 'তিন',
        'class_name': 'উচ্চ স্তর',
        'forik_no': '1',
        'father_name': '',
        'dakhila_year': '2026',
        'class_level': '20',
      },
      {
        'dakhila': '1',
        'stu_name': 'এক',
        'class_name': 'নিম্ন স্তর',
        'forik_no': '1',
        'father_name': '',
        'dakhila_year': '2026',
        'class_level': '8',
      },
      {
        'dakhila': '2',
        'stu_name': 'দুই',
        'class_name': 'মধ্য স্তর',
        'forik_no': '1',
        'father_name': '',
        'dakhila_year': '2026',
        'class_level': '10',
      },
    ]);

    expect(await DatabaseHelper.instance.getDistinctClasses(),
        ['নিম্ন স্তর', 'মধ্য স্তর', 'উচ্চ স্তর']);
  });
}
