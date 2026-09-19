import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dakhila_camera/db/database_helper.dart';
import 'package:dakhila_camera/models/document.dart';
import 'package:dakhila_camera/services/backup_service.dart';
import 'package:dakhila_camera/services/export_service.dart';
import 'package:dakhila_camera/utils/excel_parser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// ফেজ C: এক-ট্যাপ ব্যাকআপ/রিস্টোর + Excel রাউন্ড-ট্রিপ (En/Ar নাম)।
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  List<int> jpegBytes({int r = 100}) {
    final src = img.Image(width: 40, height: 40);
    img.fill(src, color: img.ColorRgb8(r, 255 - r, 128));
    return img.encodeJpg(src, quality: 90);
  }

  test('backup → ক্ষতি → restore: DB + v2 ফাইল পুরো ফিরে আসে', () async {
    final dbDir = await Directory.systemTemp.createTemp('ph_c_db');
    final appDir = await Directory.systemTemp.createTemp('ph_c_app');
    final outDir = await Directory.systemTemp.createTemp('ph_c_out');
    addTearDown(() async {
      await DatabaseHelper.instance.resetForTest();
      for (final d in [dbDir, appDir, outDir]) {
        if (await d.exists()) await d.delete(recursive: true);
      }
    });
    await databaseFactory.setDatabasesPath(dbDir.path);

    await DatabaseHelper.instance.replaceAllStudents([
      const {
        'dakhila': '281',
        'stu_name': 'মোঃ আব্দুল্লাহ',
        'class_name': 'মিশকাত',
        'forik_no': '1',
        'dakhila_year': '2026',
      },
      const {
        'dakhila': '302',
        'stu_name': 'রহিম',
        'class_name': 'মিশকাত',
        'forik_no': '1',
        'dakhila_year': '2026',
      },
    ]);

    // 281-এর ছবি v2-লেআউটে (অ্যাপ-প্রাইভেট ফোল্ডার — ব্যাকআপের মূল টার্গেট)
    final photoPath = p.join(
        appDir.path, 'DakhilaCamera', 'v2', 'মিশকাত', 'Forik_1', '281',
        'PHOTO', '281.jpg');
    await File(photoPath).parent.create(recursive: true);
    await File(photoPath).writeAsBytes(jpegBytes());
    await DatabaseHelper.instance.updateImage('281', photoPath);

    // ১) ব্যাকআপ
    final zipPath = await BackupService.backup(
      institutionName: 'আমার মাদরাসা',
      appDirPath: appDir.path,
      outDir: outDir.path,
    );
    expect(File(zipPath).existsSync(), isTrue);
    final archive = ZipDecoder().decodeBytes(File(zipPath).readAsBytesSync());
    expect(archive.files.any((f) => f.name == 'dakhila.db'), isTrue);
    expect(
        archive.files
            .any((f) => f.name.endsWith('281/PHOTO/281.jpg')),
        isTrue);

    // ২) "ক্ষতি" সিমুলেশন — ছবি-স্টেট + ফাইল দুটোই মুছে ফেলা
    await DatabaseHelper.instance.clearImage('281');
    await File(photoPath).delete();
    var s = (await DatabaseHelper.instance.getAllStudents())
        .firstWhere((s) => s.dakhila == '281');
    expect(s.isCaptured, 0);

    // ৩) রিস্টোর
    final res = await BackupService.restore(
      zipPath: zipPath,
      institutionName: 'ভুল নাম',
      appDirPath: appDir.path,
    );
    expect(res.students, 2);
    expect(res.files, greaterThanOrEqualTo(1));
    expect(res.institutionName, 'আমার মাদরাসা'); // manifest থেকে

    final docs = await DatabaseHelper.instance.getAllDocumentsMap();
    final doc = docs['281']?[DocType.PHOTO];
    expect(doc, isNotNull);
    expect(doc!.filePath, photoPath); // একই v2 পাথে ফিরে এসেছে
    expect(File(doc.filePath).existsSync(), isTrue); // ফাইলও ফিরে এসেছে

    s = (await DatabaseHelper.instance.getAllStudents())
        .firstWhere((s) => s.dakhila == '281');
    expect(s.imagePath, photoPath);
    expect(s.isCaptured, 1);
    expect(s.totalDocs, 1);
  });

  test('Excel রাউন্ড-ট্রিপ: এক্সপোর্ট → সম্পাদনা → আপডেট-ইমপোর্ট', () async {
    final dbDir = await Directory.systemTemp.createTemp('ph_c_rt_db');
    final outDir = await Directory.systemTemp.createTemp('ph_c_rt_out');
    addTearDown(() async {
      await DatabaseHelper.instance.resetForTest();
      for (final d in [dbDir, outDir]) {
        if (await d.exists()) await d.delete(recursive: true);
      }
    });
    await databaseFactory.setDatabasesPath(dbDir.path);
    await DatabaseHelper.instance.replaceAllStudents([
      const {
        'dakhila': '301',
        'stu_name': 'মোঃ আব্দুল্লাহ',
        'class_name': 'মিশকাত',
        'forik_no': '1',
        'dakhila_year': '2026',
      },
      const {
        'dakhila': '302',
        'stu_name': 'রহিম',
        'class_name': 'মিশকাত',
        'forik_no': '1',
        'dakhila_year': '2026',
      },
    ]);

    // ১) এক্সপোর্ট (Excel-এ পূর্ণ তথ্য)
    final xlsxPath = await ExportService.exportStudentsXlsx(
        outDir: outDir.path);

    // ২) "Excel-এ সম্পাদনা" সিমুলেশন: 301-এর En/Ar ভরা, 302 খালি থাকবে
    final bytes = await File(xlsxPath).readAsBytes();
    final updates =
        await ExcelParser.parseUpdateFromBytesInIsolate(bytes);
    expect(updates.length, 2);
    final u301 = updates.firstWhere((u) => u.dakhila == '301');
    expect(u301.values['stu_name'], 'মোঃ আব্দুল্লাহ'); // বাংলা কলাম পার্স হয়
    u301.values['stu_name_en'] = 'Md. Abdullah (edited)';
    u301.values['stu_name_ar'] = 'محمد عبد الله';

    // ৩) আপডেট-ইমপোর্ট
    final applied =
        await DatabaseHelper.instance.bulkApplyStudentUpdates(updates);
    expect(applied, 2);

    final all = await DatabaseHelper.instance.getAllStudents();
    final s301 = all.firstWhere((s) => s.dakhila == '301');
    expect(s301.stuNameEn, 'Md. Abdullah (edited)');
    expect(s301.stuNameAr, 'محمد عبد الله');
    final s302 = all.firstWhere((s) => s.dakhila == '302');
    expect(s302.stuName, 'রহিম'); // আপডেট হয়েছে (এক্সপোর্ট-মান), হারায়নি
    expect(s302.stuNameEn, isEmpty); // ফাইলে খালি ছিল → খালই থাকে
  });
}
