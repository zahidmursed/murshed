import 'dart:isolate';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/forik_stat.dart';
import '../models/student.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('dakhila.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(path,
        version: 2, onCreate: _createDB, onUpgrade: _upgradeDB);
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
    CREATE TABLE students(
      dakhila TEXT PRIMARY KEY,
      stu_name TEXT,
      class_name TEXT,
      forik_no TEXT,
      father_name TEXT,
      dakhila_year TEXT,
      image_path TEXT,
      is_captured INTEGER DEFAULT 0
    )
    ''');
    await _createIndexes(db);
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // ফরিক ফিল্টার/সার্চ দ্রুত করতে index
      await _createIndexes(db);
    }
  }

  Future _createIndexes(Database db) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_students_forik ON students(forik_no)',
    );
  }

  Future<void> importJsonIfEmpty() async {
    final db = await instance.database;
    final count = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM students')) ??
        0;
    if (count > 0) return;
    final String data = await rootBundle.loadString('assets/Data_basic.json');
    // 1.6MB JSON ডিকোড + হাজার খানেক রেকর্ড ম্যাপিং main isolate-এর বাইরে —
    // নাহলে প্রথম রানে UI freeze/ANR হয়।
    final List<Map<String, dynamic>> maps =
        await Isolate.run(() => Student.parseJsonToMaps(data));
    final Batch batch = db.batch();
    for (final m in maps) {
      batch.insert('students', m, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Student>> getAllStudents({String? forikFilter}) async {
    final db = await database;
    final List<Map<String, dynamic>> maps;
    if (forikFilter != null && forikFilter.isNotEmpty) {
      maps = await db.query(
        'students',
        where: 'forik_no = ?',
        whereArgs: [forikFilter],
        orderBy: 'CAST(dakhila AS INTEGER) ASC',
      );
    } else {
      maps =
          await db.query('students', orderBy: 'CAST(dakhila AS INTEGER) ASC');
    }
    return maps.map((m) => _mapToStudent(m)).toList();
  }

  Future<void> updateImage(String dakhila, String path) async {
    final db = await database;
    await db.update(
      'students',
      {'image_path': path, 'is_captured': 1},
      where: 'dakhila = ?',
      whereArgs: [dakhila],
    );
  }

  /// [forikFilter] দিলে সেই ফরিকের মধ্যেই সার্চ হবে।
  Future<List<Student>> search(String query, {String? forikFilter}) async {
    final db = await database;
    String where = '(dakhila LIKE ? OR stu_name LIKE ?)';
    final List<dynamic> args = ['%$query%', '%$query%'];
    if (forikFilter != null && forikFilter.isNotEmpty) {
      where += ' AND forik_no = ?';
      args.add(forikFilter);
    }
    final List<Map<String, dynamic>> maps = await db.query(
      'students',
      where: where,
      whereArgs: args,
      orderBy: 'CAST(dakhila AS INTEGER) ASC',
    );
    return maps.map((m) => _mapToStudent(m)).toList();
  }

  /// ক্যাপচার রিসেট — ছবি ডিলিটের পর রেকর্ড আবার "বাকি" হয়।
  Future<void> clearImage(String dakhila) async {
    final db = await database;
    await db.update(
      'students',
      {'image_path': null, 'is_captured': 0},
      where: 'dakhila = ?',
      whereArgs: [dakhila],
    );
  }

  /// ফরিক-ভিত্তিক প্রগ্রেস (মোট/তোলা) — প্রগ্রেস chips-এর জন্য।
  Future<List<ForikStat>> getForikStats() async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT forik_no, COUNT(*) AS total, '
      'COALESCE(SUM(is_captured), 0) AS captured FROM students '
      'GROUP BY forik_no ORDER BY CAST(forik_no AS INTEGER) ASC',
    );
    return rows.map(ForikStat.fromRow).toList();
  }

  Student _mapToStudent(Map<String, dynamic> m) {
    return Student(
      dakhila: (m['dakhila'] as String?) ?? '',
      stuName: (m['stu_name'] as String?) ?? '',
      className: (m['class_name'] as String?) ?? '',
      forikNo: (m['forik_no'] as String?) ?? '',
      fatherName: (m['father_name'] as String?) ?? '',
      dakhilaYear: (m['dakhila_year'] as String?) ?? '2025',
      imagePath: m['image_path'] as String?,
      isCaptured: (m['is_captured'] as int?) ?? 0,
    );
  }

  /// টেস্টে ডাটাবেস ইনস্ট্যান্স রিসেট করার জন্য।
  @visibleForTesting
  Future<void> resetForTest() async {
    final db = _database;
    _database = null;
    await db?.close();
  }
}
