import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dakhila_camera/db/database_helper.dart';
import 'package:dakhila_camera/models/document.dart';
import 'package:dakhila_camera/services/export_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  // ছোট আসল JPEG বানানোর হেল্পার
  List<int> jpegBytes({int w = 60, int h = 80, int r = 0}) {
    final src = img.Image(width: w, height: h);
    img.fill(src, color: img.ColorRgb8(r, 255 - r, 128));
    return img.encodeJpg(src, quality: 90);
  }

  test('ZIP v2 + status CSV v2 + merged PDF work end-to-end', () async {
    final dbDir = await Directory.systemTemp.createTemp('dakhila_export_db');
    final outDir = await Directory.systemTemp.createTemp('dakhila_export_out');
    addTearDown(() async {
      await DatabaseHelper.instance.resetForTest();
      if (await dbDir.exists()) await dbDir.delete(recursive: true);
      if (await outDir.exists()) await outDir.delete(recursive: true);
    });
    await databaseFactory.setDatabasesPath(dbDir.path);
    await DatabaseHelper.instance.importJsonIfEmpty();

    // 281: PHOTO (updateImage → PHOTO doc অটো) + BIRTH (upsertDocument)
    final photoPath = '${dbDir.path}/281_PHOTO.jpg';
    await File(photoPath).writeAsBytes(jpegBytes(r: 0));
    await DatabaseHelper.instance.updateImage('281', photoPath);
    final birthPath = '${dbDir.path}/281_BIRTH.jpg';
    await File(birthPath).writeAsBytes(jpegBytes(r: 200));
    await DatabaseHelper.instance.upsertDocument(StudentDocument(
      dakhila: '281',
      type: DocType.BIRTH,
      filePath: birthPath,
      ext: 'jpg',
      status: 1,
    ));

    // ZIP v2: ছাত্র-প্রতি ফোল্ডারে সব ডক + _reports
    final zipPath = await ExportService.exportZip(outDir: outDir.path);
    expect(File(zipPath).existsSync(), isTrue);
    final archive = ZipDecoder().decodeBytes(File(zipPath).readAsBytesSync());
    final names = archive.files.map((f) => f.name).toList();
    expect(names.any((n) => n.endsWith('281_PHOTO.jpg')), isTrue);
    expect(names.any((n) => n.endsWith('281_BIRTH.jpg')), isTrue);
    expect(names.any((n) => n.contains('missing.csv')), isTrue);
    expect(names.any((n) => n.contains('summary.txt')), isTrue);

    // Status CSV v2: প্রতি ছাত্রের Photo/Birth/Form কলাম
    final csvPath = await ExportService.exportMissingCsv(outDir: outDir.path);
    final content = await File(csvPath).readAsString();
    expect(content, contains('Photo'));
    expect(content, contains('Birth'));
    expect(content, contains('Form'));
    final lines = content.trim().split('\n');
    expect(lines.length, 1432); // header + 1431 ছাত্র
    final row281 = lines.firstWhere((l) => l.startsWith('281,'));
    expect(row281, contains('yes,yes'));

    // Merged PDF: ছাত্রের সব ডক এক ফাইলে
    final pdfPath = await ExportService.exportStudentMergedPdf(
        dakhila: '281', outDir: outDir.path);
    final pdfFile = File(pdfPath);
    expect(pdfFile.existsSync(), isTrue);
    expect(pdfFile.lengthSync(), greaterThan(500));
    expect(pdfPath, endsWith('.pdf'));
  });

  test('ZIP v2 throws when scope has no document files', () async {
    final dbDir = await Directory.systemTemp.createTemp('dakhila_empty_db');
    final outDir = await Directory.systemTemp.createTemp('dakhila_empty_out');
    addTearDown(() async {
      await DatabaseHelper.instance.resetForTest();
      if (await dbDir.exists()) await dbDir.delete(recursive: true);
      if (await outDir.exists()) await outDir.delete(recursive: true);
    });
    await databaseFactory.setDatabasesPath(dbDir.path);
    await DatabaseHelper.instance.importJsonIfEmpty();

    await expectLater(
      ExportService.exportZip(outDir: outDir.path),
      throwsA(isA<StateError>()),
    );
  });
}
