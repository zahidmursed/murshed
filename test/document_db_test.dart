import 'dart:io';

import 'package:dakhila_camera/db/database_helper.dart';
import 'package:dakhila_camera/models/document.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('DB v2 → v4 migration creates documents and preserves photo', () async {
    final dbDir = await Directory.systemTemp.createTemp('dakhila_doc_db');
    addTearDown(() async {
      await DatabaseHelper.instance.resetForTest();
      if (await dbDir.exists()) await dbDir.delete(recursive: true);
    });
    await databaseFactory.setDatabasesPath(dbDir.path);

    // পুরনো v2 স্কিমা হাতে তৈরি + একজন ক্যাপচার করা ছাত্র
    final db = await databaseFactory.openDatabase(
      p.join(dbDir.path, 'dakhila.db'),
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, version) async {
          await db.execute(
              'CREATE TABLE students(dakhila TEXT PRIMARY KEY, stu_name TEXT, '
              'class_name TEXT, forik_no TEXT, father_name TEXT, dakhila_year TEXT, '
              'image_path TEXT, is_captured INTEGER DEFAULT 0)');
          await db
              .execute('CREATE INDEX idx_students_forik ON students(forik_no)');
        },
      ),
    );
    await db.insert('students', {
      'dakhila': '281',
      'stu_name': 'পুরনো রেকর্ড',
      'class_name': 'মিশকাত',
      'forik_no': '1',
      'dakhila_year': '2025',
      'image_path': '/old/281.jpg',
      'is_captured': 1,
    });
    await db.close();

    // DatabaseHelper খুললে 2 → 4 upgrade চলবে
    final helper = DatabaseHelper.instance;
    final docs = await helper.getAllDocumentsMap();
    expect(docs['281']?[DocType.PHOTO]?.filePath, '/old/281.jpg');

    final students = await helper.getAllStudents();
    final s281 = students.firstWhere((s) => s.dakhila == '281');
    expect(s281.totalDocs, 1);
    expect(s281.isCaptured, 1);

    // BIRTH doc যোগ → total_docs 2
    await helper.upsertDocument(const StudentDocument(
      dakhila: '281',
      type: DocType.BIRTH,
      filePath: '/x/281_BIRTH.pdf',
      ext: 'pdf',
      mimeType: 'application/pdf',
    ));
    final afterBirth = await helper.getAllStudents();
    expect(afterBirth.firstWhere((s) => s.dakhila == '281').totalDocs, 2);

    // ছবি মুছলে PHOTO doc বাদ, BIRTH থাকে (total_docs 1)
    await helper.clearImage('281');
    final afterClear = await helper.getAllStudents();
    final cleared = afterClear.firstWhere((s) => s.dakhila == '281');
    expect(cleared.isCaptured, 0);
    expect(cleared.totalDocs, 1);
    final docsAfterClear = await helper.getAllDocumentsMap();
    expect(docsAfterClear['281']!.containsKey(DocType.PHOTO), isFalse);
    expect(docsAfterClear['281']!.containsKey(DocType.BIRTH), isTrue);
  });

  test('fresh DB creates v4 schema with documents table', () async {
    final dbDir = await Directory.systemTemp.createTemp('dakhila_doc_fresh');
    addTearDown(() async {
      await DatabaseHelper.instance.resetForTest();
      if (await dbDir.exists()) await dbDir.delete(recursive: true);
    });
    await databaseFactory.setDatabasesPath(dbDir.path);
    await DatabaseHelper.instance.importJsonIfEmpty();

    final db = await DatabaseHelper.instance.database;
    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='documents'");
    expect(tables, isNotEmpty);
  });
}
