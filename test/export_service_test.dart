import 'dart:io';

import 'package:dakhila_camera/db/database_helper.dart';
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

  test('ZIP, missing CSV and PDF sheet export work end-to-end', () async {
    final dbDir = await Directory.systemTemp.createTemp('dakhila_export_db');
    final outDir = await Directory.systemTemp.createTemp('dakhila_export_out');
    addTearDown(() async {
      await DatabaseHelper.instance.resetForTest();
      if (await dbDir.exists()) await dbDir.delete(recursive: true);
      if (await outDir.exists()) await outDir.delete(recursive: true);
    });
    await databaseFactory.setDatabasesPath(dbDir.path);
    await DatabaseHelper.instance.importJsonIfEmpty();

    // 281-কে তোলা হিসেবে চিহ্নিত + আসল ছোট JPEG ফাইল তৈরি
    final src = img.Image(width: 60, height: 80);
    img.fill(src, color: img.ColorRgb8(0, 255, 0));
    final photo = File('${dbDir.path}/281.jpg');
    await photo.writeAsBytes(img.encodeJpg(src, quality: 90));
    await DatabaseHelper.instance.updateImage('281', photo.path);

    // ZIP এক্সপোর্ট
    final zipPath = await ExportService.exportZip(outDir: outDir.path);
    expect(File(zipPath).existsSync(), isTrue);
    expect(File(zipPath).lengthSync(), greaterThan(200));
    expect(zipPath, endsWith('.zip'));

    // Missing CSV — 281 বাদে বাকি সবাই (1430)
    final csvPath = await ExportService.exportMissingCsv(outDir: outDir.path);
    final csvContent = await File(csvPath).readAsString();
    final lines = csvContent.trim().split('\n');
    expect(lines.first, contains('Dakhila'));
    expect(lines.length, 1431); // header + 1430 missing
    expect(
      lines.where((l) => l.startsWith('281,') || l.startsWith('"281"')),
      isEmpty,
    );
    expect(csvPath, endsWith('.csv'));

    // PDF প্রিন্ট শিট
    final pdfPath = await ExportService.exportPdfSheet(outDir: outDir.path);
    final pdfFile = File(pdfPath);
    expect(pdfFile.existsSync(), isTrue);
    expect(pdfFile.lengthSync(), greaterThan(500));
    expect(pdfPath, endsWith('.pdf'));
  });
}
