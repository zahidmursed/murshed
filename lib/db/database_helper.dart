import 'dart:isolate';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/document.dart';
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
        version: 6, onCreate: _createDB, onUpgrade: _upgradeDB);
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
    CREATE TABLE students(
      dakhila TEXT PRIMARY KEY,
      stu_name TEXT,
      class_name TEXT,
      forik_no TEXT,
      father_name TEXT,
      guardian_mobile TEXT,
      dakhila_year TEXT,
      class_level TEXT,
      marhala TEXT,
      exam_year TEXT,
      image_path TEXT,
      is_captured INTEGER DEFAULT 0,
      total_docs INTEGER DEFAULT 0
    )
    ''');
    await _createIndexes(db);
    await _createDocumentsTable(db);
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // ফরিক ফিল্টার/সার্চ দ্রুত করতে index
      await _createIndexes(db);
    }
    if (oldVersion < 4) {
      await _upgradeToV4(db);
    }
    if (oldVersion < 5) {
      await _upgradeToV5(db);
    }
    if (oldVersion < 6) {
      await _upgradeToV6(db);
    }
  }

  /// v2/v3 → v4: নতুন কলাম + documents টেবিল + পুরনো ছবি PHOTO doc হিসেবে
  /// মাইগ্রেট (copy-not-move, idempotent — INSERT OR IGNORE)।
  Future _upgradeToV4(Database db) async {
    await _addColumnIfMissing(db, 'students', 'marhala TEXT');
    await _addColumnIfMissing(db, 'students', 'exam_year TEXT');
    await _addColumnIfMissing(db, 'students', 'total_docs INTEGER DEFAULT 0');
    await _createDocumentsTable(db);
    await db.execute('''
    INSERT OR IGNORE INTO documents
      (dakhila, doc_type, file_path, file_ext, mime_type, status, updated_at)
    SELECT dakhila, 'PHOTO', image_path, 'jpg', 'image/jpeg', 1, NULL
    FROM students
    WHERE image_path IS NOT NULL AND image_path != ''
    ''');
    await db.execute(
        'UPDATE students SET total_docs = (SELECT COUNT(*) FROM documents '
        'WHERE documents.dakhila = students.dakhila)');
  }

  /// v4 → v5: অভিভাবকের মোবাইল নম্বর যোগ করে, আগে থেকে থাকা bundled
  /// ছাত্র-রেকর্ডগুলোর নম্বরও dakhila মিলিয়ে বসায়।
  Future _upgradeToV5(Database db) async {
    await _addColumnIfMissing(db, 'students', 'guardian_mobile TEXT');
    final raw = await rootBundle.loadString('assets/Data_basic.json');
    final maps = await Isolate.run(() => Student.parseJsonToMaps(raw));
    final batch = db.batch();
    for (final student in maps) {
      final phone = student['guardian_mobile'] as String? ?? '';
      if (phone.isEmpty) continue;
      batch.update(
        'students',
        {'guardian_mobile': phone},
        where: 'dakhila = ?',
        whereArgs: [student['dakhila']],
      );
    }
    await batch.commit(noResult: true);
  }

  /// v5 → v6: dropdown-এর শিক্ষা-ক্রম `CLASS_LEVEL` bundled data থেকে যোগ।
  Future _upgradeToV6(Database db) async {
    await _addColumnIfMissing(db, 'students', 'class_level TEXT');
    final raw = await rootBundle.loadString('assets/Data_basic.json');
    final maps = await Isolate.run(() => Student.parseJsonToMaps(raw));
    final batch = db.batch();
    for (final student in maps) {
      final dakhila = student['dakhila'] as String? ?? '';
      final level = student['class_level'] as String? ?? '';
      if (dakhila.isEmpty || level.isEmpty) continue;
      batch.update('students', {'class_level': level},
          where: 'dakhila = ?', whereArgs: [dakhila]);
    }
    await batch.commit(noResult: true);
  }

  Future _createDocumentsTable(Database db) async {
    await db.execute('''
    CREATE TABLE IF NOT EXISTS documents(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      dakhila TEXT NOT NULL,
      doc_type TEXT NOT NULL CHECK(doc_type IN ('PHOTO','BIRTH','FORM')),
      file_path TEXT NOT NULL,
      file_ext TEXT NOT NULL,
      mime_type TEXT,
      file_size INTEGER,
      status INTEGER DEFAULT 1,
      updated_at TEXT,
      FOREIGN KEY(dakhila) REFERENCES students(dakhila) ON DELETE CASCADE,
      UNIQUE(dakhila, doc_type)
    )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_doc_dakhila_type ON documents(dakhila, doc_type)');
  }

  Future _addColumnIfMissing(
      Database db, String table, String columnDef) async {
    final cols = await db.rawQuery('PRAGMA table_info($table)');
    final names = cols.map((c) => (c['name'] as String?) ?? '').toSet();
    final name = columnDef.split(' ').first;
    if (!names.contains(name)) {
      await db.execute('ALTER TABLE $table ADD COLUMN $columnDef');
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

  Future<List<Student>> getAllStudents(
      {String? forikFilter, String? classFilter}) async {
    final db = await database;
    final where = <String>[];
    final args = <dynamic>[];
    if (classFilter != null && classFilter.isNotEmpty) {
      where.add('class_name = ?');
      args.add(classFilter);
    }
    if (forikFilter != null && forikFilter.isNotEmpty) {
      where.add('forik_no = ?');
      args.add(forikFilter);
    }
    final maps = await db.query(
      'students',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: where.isEmpty ? null : args,
      orderBy: 'CAST(dakhila AS INTEGER) ASC',
    );
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
    // 3-Doc: PHOTO ডকুমেন্ট হিসেবেও সেভ (total_docs recalc সহ)
    final ext = path.contains('.') ? path.split('.').last.toLowerCase() : 'jpg';
    await upsertDocument(StudentDocument(
      dakhila: dakhila,
      type: DocType.PHOTO,
      filePath: path,
      ext: ext,
      mimeType: 'image/jpeg',
      status: 1,
    ));
  }

  /// ডকুমেন্ট INSERT OR REPLACE + students.total_docs recalc।
  Future<void> upsertDocument(StudentDocument doc) async {
    final db = await database;
    await db.insert('documents', doc.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    await _recalcTotalDocs(db, doc.dakhila);
  }

  /// নির্দিষ্ট টাইপের ডকুমেন্ট মুছে ফেলে + total_docs recalc।
  Future<void> deleteDocument(String dakhila, DocType type) async {
    final db = await database;
    await db.delete('documents',
        where: 'dakhila = ? AND doc_type = ?', whereArgs: [dakhila, type.name]);
    await _recalcTotalDocs(db, dakhila);
  }

  /// সব ডকুমেন্ট: dakhila → (DocType → StudentDocument)।
  Future<Map<String, Map<DocType, StudentDocument>>>
      getAllDocumentsMap() async {
    final db = await database;
    final rows = await db.query('documents');
    final map = <String, Map<DocType, StudentDocument>>{};
    for (final r in rows) {
      final doc = StudentDocument.fromRow(r);
      map.putIfAbsent(doc.dakhila, () => {})[doc.type] = doc;
    }
    return map;
  }

  Future<void> _recalcTotalDocs(Database db, String dakhila) async {
    final count = Sqflite.firstIntValue(await db.rawQuery(
            'SELECT COUNT(*) FROM documents WHERE dakhila = ? AND status = 1',
            [dakhila])) ??
        0;
    await db.update('students', {'total_docs': count},
        where: 'dakhila = ?', whereArgs: [dakhila]);
  }

  /// [forikFilter]/[classFilter] দিলে সেই সীমার মধ্যেই সার্চ হবে।
  Future<List<Student>> search(String query,
      {String? forikFilter, String? classFilter}) async {
    final db = await database;
    // ফিক্স: LIKE wildcard escape — ব্যবহারকারীর %/_ লিখলে আক্ষরিক অক্ষর হিসেবে
    // ম্যাচ হয় (নইলে '%' দিলে সবাই, '_' দিলে যেকোনো এক অক্ষর ম্যাচ করত)।
    final escaped = query
        .replaceAll('\\', '\\\\')
        .replaceAll('%', '\\%')
        .replaceAll('_', '\\_');
    String where = "(dakhila LIKE ? ESCAPE '\\' OR stu_name LIKE ? ESCAPE '\\')";
    final List<dynamic> args = ['%$escaped%', '%$escaped%'];
    if (classFilter != null && classFilter.isNotEmpty) {
      where += ' AND class_name = ?';
      args.add(classFilter);
    }
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
    // PHOTO ডকুমেন্টও বাদ (total_docs recalc সহ)
    await db.delete('documents',
        where: 'dakhila = ? AND doc_type = ?',
        whereArgs: [dakhila, DocType.PHOTO.name]);
    await db.update(
      'students',
      {'image_path': null, 'is_captured': 0},
      where: 'dakhila = ?',
      whereArgs: [dakhila],
    );
    await _recalcTotalDocs(db, dakhila);
  }

  /// ফরিক-ভিত্তিক প্রগ্রেস (মোট/তোলা) — প্রগ্রেস chips-এর জন্য।
  Future<List<ForikStat>> getForikStats({String? classFilter}) async {
    final db = await database;
    String where = '';
    final args = <dynamic>[];
    if (classFilter != null && classFilter.isNotEmpty) {
      where = 'WHERE class_name = ?';
      args.add(classFilter);
    }
    final rows = await db.rawQuery(
      'SELECT forik_no, COUNT(*) AS total, '
      'COALESCE(SUM(is_captured), 0) AS captured FROM students $where '
      'GROUP BY forik_no ORDER BY CAST(forik_no AS INTEGER) ASC',
      args.isEmpty ? null : args,
    );
    return rows.map(ForikStat.fromRow).toList();
  }

  /// ডিস্টিংক্ট ক্লাস লিস্ট — ক্লাস ফিল্টার dropdown-এর জন্য।
  Future<List<String>> getDistinctClasses() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT class_name,
             MIN(CAST(NULLIF(class_level, '') AS INTEGER)) AS level_order
      FROM students
      WHERE class_name IS NOT NULL AND class_name != ''
      GROUP BY class_name
      ORDER BY level_order IS NULL ASC, level_order ASC, class_name COLLATE NOCASE ASC
    ''');
    return rows
        .map((r) => (r['class_name'] as String?) ?? '')
        .where((c) => c.isNotEmpty)
        .toList();
  }

  /// ক্লাসভিত্তিক ফরিক লিস্ট (ক্লাস null হলে সব ফরিক)।
  Future<List<String>> getForiksForClass({String? className}) async {
    final db = await database;
    String where = "forik_no IS NOT NULL AND forik_no != ''";
    final args = <dynamic>[];
    if (className != null && className.isNotEmpty) {
      where += ' AND class_name = ?';
      args.add(className);
    }
    final rows = await db.rawQuery(
      'SELECT DISTINCT forik_no FROM students WHERE $where '
      'ORDER BY CAST(forik_no AS INTEGER) ASC',
      args.isEmpty ? null : args,
    );
    return rows
        .map((r) => (r['forik_no'] as String?) ?? '')
        .where((f) => f.isNotEmpty)
        .toList();
  }

  /// কাস্টম ইমপোর্ট: পুরনো ডেটার বদলে নতুন ডেটা বসে (এক ট্রানজেকশনে)।
  /// একই দাখিলা নতুন ডেটাতে থাকলে তোলা ছবির স্ট্যাটাস প্রিজার্ভ হয়।
  Future<int> replaceAllStudents(List<Map<String, dynamic>> maps) async {
    final db = await database;
    var imported = 0;
    await db.transaction((txn) async {
      final old = await txn.query(
        'students',
        columns: ['dakhila', 'image_path', 'is_captured'],
      );
      final captureByDakhila = <String, String?>{
        for (final r in old)
          if ((r['is_captured'] as int?) == 1)
            (r['dakhila'] as String? ?? ''): r['image_path'] as String?,
      };
      await txn.delete('students');
      final batch = txn.batch();
      for (final source in maps) {
        // defensive copy — কলারের ম্যাপে টাইপ ভিন্ন হলেও নিরাপদ
        final m = Map<String, dynamic>.from(source);
        final dakhila = m['dakhila'] as String? ?? '';
        if (captureByDakhila.containsKey(dakhila)) {
          m['image_path'] = captureByDakhila[dakhila];
          m['is_captured'] = 1;
        }
        batch.insert('students', m,
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
      // নতুন ডেটায় নেই এমন দাখিলার documents বাদ + total_docs recalc
      await txn.execute(
          'DELETE FROM documents WHERE dakhila NOT IN (SELECT dakhila FROM students)');
      await txn.execute(
          'UPDATE students SET total_docs = (SELECT COUNT(*) FROM documents '
          'WHERE documents.dakhila = students.dakhila)');
      imported = maps.length;
    });
    return imported;
  }

  /// সব রেকর্ড মুছে ফেলে — পরের load()-এ বান্ডেল ডেটা আবার ইমপোর্ট হবে।
  Future<void> deleteAllStudents() async {
    final db = await database;
    await db.delete('students');
  }

  Student _mapToStudent(Map<String, dynamic> m) {
    return Student(
      dakhila: (m['dakhila'] as String?) ?? '',
      stuName: (m['stu_name'] as String?) ?? '',
      className: (m['class_name'] as String?) ?? '',
      forikNo: (m['forik_no'] as String?) ?? '',
      fatherName: (m['father_name'] as String?) ?? '',
      guardianMobile: (m['guardian_mobile'] as String?) ?? '',
      dakhilaYear: (m['dakhila_year'] as String?) ?? '${DateTime.now().year}',
      classLevel: (m['class_level'] as String?) ?? '',
      marhala: (m['marhala'] as String?) ?? '',
      examYear: (m['exam_year'] as String?) ?? '',
      imagePath: m['image_path'] as String?,
      isCaptured: (m['is_captured'] as int?) ?? 0,
      totalDocs: (m['total_docs'] as int?) ?? 0,
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
