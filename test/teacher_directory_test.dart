import 'package:dakhila_camera/services/teacher_directory.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

/// ইন-মেমোরি শিক্ষক-এক্সেল: ফরিক-নির্দিষ্ট + ক্লাস-লেভেল + নরমালাইজ কেস।
List<int> _teacherXlsx() {
  final excel = Excel.createExcel(); // ডিফল্ট 'Sheet1' খালি থাকবে
  final sheet = excel['Teacher Name'];
  sheet.appendRow([
    TextCellValue('SL'),
    TextCellValue('CLASS_NAME'),
    TextCellValue('FORIK_NAME'),
    TextCellValue('TEACHER_NAME_B'),
    TextCellValue('TEACHER_NAME'),
    TextCellValue('MOBILE_NO'),
  ]);
  sheet.appendRow([
    const IntCellValue(1),
    TextCellValue('হিফয সবকী'),
    TextCellValue('1'),
    TextCellValue('মাওঃ আ'),
    TextCellValue('A'),
    TextCellValue('01711 000001'), // স্পেসসহ → 01711000001
  ]);
  sheet.appendRow([
    const IntCellValue(2),
    TextCellValue('হিফয সবকী'),
    TextCellValue('2'),
    TextCellValue('মাওঃ ব'),
    TextCellValue('B'),
    TextCellValue('1745682855'), // leading 0 নেই → 01745682855
  ]);
  sheet.appendRow([
    const IntCellValue(3),
    TextCellValue('ইফতা'),
    TextCellValue(''), // ফরিক-উদাসীন (পুরো ক্লাস)
    TextCellValue('মাওঃ ক'),
    TextCellValue('C'),
    TextCellValue('01913 379742'),
  ]);
  sheet.appendRow([
    const IntCellValue(4),
    TextCellValue('বোর্ড-  জানুয়ারী'), // ডাবল স্পেস → normalize হবে
    TextCellValue(''),
    TextCellValue('মাওঃ ঘ'),
    TextCellValue('D'),
    const IntCellValue(0), // মোবাইল নেই
  ]);
  return excel.encode()!;
}

void main() {
  test('parses rows, skips empty default sheet, normalizes mobile', () {
    final teachers = TeacherDirectory.parseFromBytes(_teacherXlsx());
    expect(teachers.length, 4);
    expect(teachers[0].className, 'হিফয সবকী');
    expect(teachers[0].forik, '1');
    expect(teachers[0].mobile, '01711000001'); // স্পেস বাদ
    expect(teachers[1].mobile, '01745682855'); // leading 0 যোগ
    expect(teachers[3].className, 'বোর্ড- জানুয়ারী'); // ডাবল-স্পেস collapse
    expect(teachers[3].mobile, ''); // মোবাইল না থাকলে খালি
    expect(teachers[3].displayName, 'মাওঃ ঘ');
  });

  test('find: exact forik match wins', () {
    final teachers = TeacherDirectory.parseFromBytes(_teacherXlsx());
    final t = TeacherDirectory.find(teachers, 'হিফয সবকী', '2');
    expect(t, isNotNull);
    expect(t!.nameBn, 'মাওঃ ব');
  });

  test('find: forik numeric equivalence ("02" == "2")', () {
    final teachers = TeacherDirectory.parseFromBytes(_teacherXlsx());
    final t = TeacherDirectory.find(teachers, 'হিফয সবকী', '02');
    expect(t!.nameBn, 'মাওঃ ব');
  });

  test('find: falls back to class-level (FORIK খালি) entry', () {
    final teachers = TeacherDirectory.parseFromBytes(_teacherXlsx());
    final t = TeacherDirectory.find(teachers, 'ইফতা', '5');
    expect(t!.nameBn, 'মাওঃ ক');
    // ফরিক খালি হলেও ক্লাস-লেভেল শিক্ষকই আসবে
    expect(TeacherDirectory.find(teachers, 'ইফতা', '')!.nameBn, 'মাওঃ ক');
  });

  test('find: no match → null (class unknown / forik unknown)', () {
    final teachers = TeacherDirectory.parseFromBytes(_teacherXlsx());
    expect(TeacherDirectory.find(teachers, 'মিশকাত', '1'), isNull);
    // হিফয সবকী-র কোনো ক্লাস-লেভেল রো নেই, আর forik 3-ও নেই
    expect(TeacherDirectory.find(teachers, 'হিফয সবকী', '3'), isNull);
    expect(TeacherDirectory.find(teachers, '', '1'), isNull);
    expect(TeacherDirectory.find(null, 'ইফতা', '1'), isNull);
  });

  test('find: whitespace-normalized class matches ("বোর্ড-  জানুয়ারী")', () {
    final teachers = TeacherDirectory.parseFromBytes(_teacherXlsx());
    final t = TeacherDirectory.find(teachers, 'বোর্ড- জানুয়ারী', '');
    expect(t!.nameBn, 'মাওঃ ঘ');
  });
}
