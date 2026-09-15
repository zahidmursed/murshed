import 'package:dakhila_camera/utils/excel_parser.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseFromBytes maps Excel headers to DB schema (case-insensitive)', () {
    final excel = Excel.createExcel();
    final sheet = excel['Sheet1'];
    sheet.appendRow([
      TextCellValue('Name'),
      TextCellValue('Dakhila'),
      TextCellValue('Forik'),
      TextCellValue('Class'),
      TextCellValue('Father'),
      TextCellValue('Gar Mob No'),
    ]);
    sheet.appendRow([
      TextCellValue('আহমেদ'),
      const IntCellValue(281),
      TextCellValue('3'),
      TextCellValue('মিশকাত'),
      TextCellValue('করিম'),
      TextCellValue('01700111222'),
    ]);
    sheet.appendRow([
      TextCellValue('রাহিম'),
      TextCellValue('282'),
      TextCellValue('3'),
      TextCellValue('মিশকাত'),
      TextCellValue('রহিম'),
      TextCellValue('01800111222'),
    ]);
    final bytes = excel.encode()!;

    final maps = ExcelParser.parseFromBytes(bytes);

    expect(maps.length, 2);
    expect(maps[0]['dakhila'], '281'); // IntCellValue → string হয়ে যায়
    expect(maps[0]['stu_name'], 'আহমেদ');
    expect(maps[0]['forik_no'], '3');
    expect(maps[0]['class_name'], 'মিশকাত');
    expect(maps[0]['guardian_mobile'], '01700111222');
    expect(maps[1]['dakhila'], '282');
    expect(maps[1]['father_name'], 'রহিম');
    expect(maps[1]['guardian_mobile'], '01800111222');
  });

  test('rows without dakhila are skipped', () {
    final excel = Excel.createExcel();
    final sheet = excel['Sheet1'];
    sheet.appendRow([
      TextCellValue('DAKHILA'),
      TextCellValue('STU_NAME'),
    ]);
    sheet.appendRow([
      TextCellValue(''),
      TextCellValue('নাম আছে কিন্তু দাখিলা নেই'),
    ]);
    sheet.appendRow([
      TextCellValue('500'),
      TextCellValue('বৈধ রেকর্ড'),
    ]);
    final maps = ExcelParser.parseFromBytes(excel.encode()!);
    expect(maps.length, 1);
    expect(maps.first['dakhila'], '500');
  });

  test('throws when no DAKHILA column exists', () {
    final excel = Excel.createExcel();
    final sheet = excel['Sheet1'];
    sheet.appendRow([TextCellValue('NAME')]);
    sheet.appendRow([TextCellValue('x')]);
    expect(
      () => ExcelParser.parseFromBytes(excel.encode()!),
      throwsFormatException,
    );
  });

  test('CLASS_LEVEL/MARHALA/EXAM_YEAR columns are preserved (dropdown order)', () {
    final excel = Excel.createExcel();
    final sheet = excel['Sheet1'];
    sheet.appendRow([
      TextCellValue('DAKHILA'),
      TextCellValue('STU_NAME'),
      TextCellValue('CLASS_NAME'),
      TextCellValue('CLASS_LEVEL'),
      TextCellValue('MARHALA'),
      TextCellValue('EXAM_YEAR'),
    ]);
    sheet.appendRow([
      TextCellValue('601'),
      TextCellValue('ছাত্র'),
      TextCellValue('হিফজ'),
      TextCellValue('2'),
      TextCellValue('তাখাসুসুস্সানা'),
      TextCellValue('2026'),
    ]);
    final maps = ExcelParser.parseFromBytes(excel.encode()!);
    expect(maps.first['class_level'], '2');
    expect(maps.first['marhala'], 'তাখাসুসুস্সানা');
    expect(maps.first['exam_year'], '2026');
  });
}
