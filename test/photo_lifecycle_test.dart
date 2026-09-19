import 'dart:io';

import 'package:dakhila_camera/db/database_helper.dart';
import 'package:dakhila_camera/models/document.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// ছবি-লাইফসাইকেল সামঞ্জস্য (students.image_path ↔ documents টেবিল):
/// updateImage/clearImage/deleteDocument — সব পথে total_docs ও ডক-ম্যাপ
/// সঠিক থাকা চাই (একবার ভুল "ফিক্স" এড়াতে স্থায়ী রিগ্রেশন-টেস্ট)।
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    final tmpDir = await Directory.systemTemp.createTemp('dakhila_photo_lc');
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
    ]);
  });

  test('updateImage mirrors into PHOTO doc and recalcs total_docs', () async {
    final db = DatabaseHelper.instance;
    final photoPath = '${Directory.systemTemp.path}/lc_281.jpg';
    addTearDown(() async {
      final f = File(photoPath);
      if (await f.exists()) await f.delete();
    });
    final src = img.Image(width: 40, height: 40);
    img.fill(src, color: img.ColorRgb8(120, 60, 30));
    await File(photoPath).writeAsBytes(img.encodeJpg(src, quality: 90));

    await db.updateImage('281', photoPath);

    final docs = await db.getAllDocumentsMap();
    expect(docs['281']?[DocType.PHOTO], isNotNull);
    expect(docs['281']![DocType.PHOTO]!.filePath, photoPath);

    final s = (await db.getAllStudents()).firstWhere((s) => s.dakhila == '281');
    expect(s.imagePath, photoPath);
    expect(s.isCaptured, 1);
    expect(s.totalDocs, 1);
  });

  test('clearImage removes PHOTO doc row, resets student, recalcs', () async {
    final db = DatabaseHelper.instance;
    final photoPath = '${Directory.systemTemp.path}/lc2_281.jpg';
    final src = img.Image(width: 40, height: 40);
    img.fill(src, color: img.ColorRgb8(10, 200, 30));
    await File(photoPath).writeAsBytes(img.encodeJpg(src, quality: 90));
    await db.updateImage('281', photoPath);

    await db.clearImage('281');

    final docs = await db.getAllDocumentsMap();
    expect(docs['281']?[DocType.PHOTO], isNull); // রেকর্ড সত্যিই মুছে যায়
    final s = (await db.getAllStudents()).firstWhere((s) => s.dakhila == '281');
    expect(s.imagePath, isNull);
    expect(s.isCaptured, 0);
    expect(s.totalDocs, 0);
  });

  test('deleteDocument recalculates total_docs (BIRTH/FORM)', () async {
    final db = DatabaseHelper.instance;
    Future<void> add(DocType type) => db.upsertDocument(StudentDocument(
          dakhila: '281',
          type: type,
          filePath: '${Directory.systemTemp.path}/lc3_281_${type.name}.jpg',
          ext: 'jpg',
          status: 1,
        ));
    await add(DocType.BIRTH);
    await add(DocType.FORM);

    var s = (await db.getAllStudents()).firstWhere((s) => s.dakhila == '281');
    expect(s.totalDocs, 2);

    await db.deleteDocument('281', DocType.FORM);
    s = (await db.getAllStudents()).firstWhere((s) => s.dakhila == '281');
    expect(s.totalDocs, 1);
  });
}
