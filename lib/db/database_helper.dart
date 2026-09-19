import 'dart:isolate';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/document.dart';
import '../models/case_note.dart';
import '../models/forik_stat.dart';
import '../models/student.dart';
import '../models/teacher.dart';
import '../services/teacher_directory.dart';

/// replaceAllStudents()-এর ফল-রিপোর্ট (Phase 1 H2 collision-গার্ড)।
class ReplaceReport {
  /// ইমপোর্ট হওয়া রেকর্ড সংখ্যা (replaceAllStudents শেষে সেট হয়)।
  int imported = 0;

  /// দাখিলা একই কিন্তু বছর-জোড়া (dakhila_year|exam_year) ভিন্ন — এই
  /// দাখিলাগুলোর পুরনো ছবি/সম্পাদনা/ডক নতুন ছাত্রের নামে বসেনি।
  /// UI-তে ইউজারকে দেখানো হয় যেন নতুন ব্যাচের এই ছাত্রদের ছবি নতুন করে তোলা হয়।
  final List<String> collisions = <String>[];
}

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('dakhila.db');
    return _database!;
  }

  /// ব্যাকআপ/রিস্টোরের জন্য — DB বন্ধ (পরের অ্যাক্সেসে স্বয়ংক্রিয়ভাবে
  /// আবার খোলা হবে)।
  Future<void> close() async {
    final db = _database;
    _database = null;
    await db?.close();
  }

  /// চলমান DB ফাইল-পাথ (ব্যাকআপ/রিস্টোরের জন্য)।
  Future<String> databaseFilePath() async =>
      join(await getDatabasesPath(), 'dakhila.db');

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(
      path,
      version: 12,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
      // ইন্টিগ্রিটি ফিক্স: schema-তে documents → students ON DELETE CASCADE লেখা
      // থাকলেও PRAGMA foreign_keys=ON ছাড়া SQLite সেটা প্রয়োগ করে না — ফলে
      // students মুছলে documents rows অনাথ (orphan) হয়ে পড়ে থাকত।
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
    );
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
      mother_name TEXT,
      birth_date TEXT,
      birth_certificate_no TEXT,
      stu_name_en TEXT,
      stu_name_ar TEXT,
      father_name_en TEXT,
      father_name_ar TEXT,
      mother_name_en TEXT,
      mother_name_ar TEXT,
      is_edited INTEGER DEFAULT 0,
      avg_num_month TEXT,
      avg_num_1st TEXT,
      avg_num_2nd TEXT,
      avg_num_final TEXT,
      address_vill TEXT,
      address_po TEXT,
      address_ps TEXT,
      address_dist TEXT,
      image_path TEXT,
      is_captured INTEGER DEFAULT 0,
      total_docs INTEGER DEFAULT 0
    )
    ''');
    await _createIndexes(db);
    await _createDocumentsTable(db);
    await _createTeachersTable(db);
    await _seedTeachersFromAsset(db);
    await _createCaseNotesTable(db);
    await _createNameCacheTable(db);
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
    if (oldVersion < 7) {
      await _upgradeToV7(db);
    }
    if (oldVersion < 8) {
      await _upgradeToV8(db);
    }
    if (oldVersion < 9) {
      await _upgradeToV9(db);
    }
    if (oldVersion < 10) {
      await _upgradeToV10(db);
    }
    if (oldVersion < 11) {
      await _upgradeToV11(db);
    }
    if (oldVersion < 12) {
      await _upgradeToV12(db);
    }
  }

  /// v11 → v12: নাম-ক্যাশ — ব্যবহারকারী-নিশ্চিত (বাংলা → ইংরেজি, আরবী)
  /// পূর্ণনাম-জোড়া; পরেরবার এক-ট্যাপে নির্ভুল অটো-ফিলের জন্য।
  Future _upgradeToV12(Database db) async {
    await _createNameCacheTable(db);
  }

  Future _createNameCacheTable(Database db) async {
    await db.execute('''
    CREATE TABLE IF NOT EXISTS name_cache(
      bangla TEXT PRIMARY KEY,
      english TEXT NOT NULL,
      arabic TEXT NOT NULL,
      updated_at TEXT
    )
    ''');
  }

  /// v10 → v11: নামের ইংরেজি/আরবী রূপ — রিপোর্ট ফরম ও ভবিষ্যৎ
  /// Excel-এক্সপোর্টের জন্য (ছাত্র/পিতা/মাতা × ইংরেজি/আরবী)।
  Future _upgradeToV11(Database db) async {
    await _addColumnIfMissing(db, 'students', 'stu_name_en TEXT');
    await _addColumnIfMissing(db, 'students', 'stu_name_ar TEXT');
    await _addColumnIfMissing(db, 'students', 'father_name_en TEXT');
    await _addColumnIfMissing(db, 'students', 'father_name_ar TEXT');
    await _addColumnIfMissing(db, 'students', 'mother_name_en TEXT');
    await _addColumnIfMissing(db, 'students', 'mother_name_ar TEXT');
  }

  /// v9 → v10: ছাত্র-প্রতি কেস নোট টেবিল (আলাদা — ইমপোর্ট/রিসেটে হারায় না)।
  Future _upgradeToV10(Database db) async {
    await _createCaseNotesTable(db);
  }

  /// v8 → v9: মাতা/জন্মতারিখ/জন্মসনদ নম্বর + `is_edited` ফ্ল্যাগ;
  /// আগে থেকে থাকা bundled রেকর্ডের মানও dakhila মিলিয়ে বসায়।
  Future _upgradeToV9(Database db) async {
    await _addColumnIfMissing(db, 'students', 'mother_name TEXT');
    await _addColumnIfMissing(db, 'students', 'birth_date TEXT');
    await _addColumnIfMissing(db, 'students', 'birth_certificate_no TEXT');
    await _addColumnIfMissing(db, 'students', 'is_edited INTEGER DEFAULT 0');
    final raw = await rootBundle.loadString('assets/Data_basic.json');
    final maps = await Isolate.run(() => Student.parseJsonToMaps(raw));
    final batch = db.batch();
    for (final student in maps) {
      final dakhila = student['dakhila'] as String? ?? '';
      if (dakhila.isEmpty) continue;
      final hasValue = const [
        'mother_name',
        'birth_date',
        'birth_certificate_no'
      ].any((k) => (student[k] as String? ?? '').isNotEmpty);
      if (!hasValue) continue;
      batch.update(
          'students',
          {
            'mother_name': student['mother_name'],
            'birth_date': student['birth_date'],
            'birth_certificate_no': student['birth_certificate_no'],
          },
          where: 'dakhila = ?',
          whereArgs: [dakhila]);
    }
    await batch.commit(noResult: true);
  }

  /// v7 → v8: শিক্ষক-তালিকার `teachers` টেবিল (অ্যাপে সম্পাদনাযোগ্য) +
  /// bundled xlsx থেকে প্রথমবার সিড।
  Future _upgradeToV8(Database db) async {
    await _createTeachersTable(db);
    await _seedTeachersFromAsset(db);
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

  /// v6 → v7: রিপোর্ট ফরমের পরীক্ষার নম্বর (মাসিক/সাময়িক/বার্ষিক) +
  /// ঠিকানা কলাম যোগ; আগে থেকে থাকা bundled রেকর্ডগুলোর মানও dakhila মিলিয়ে বসায়।
  Future _upgradeToV7(Database db) async {
    await _addColumnIfMissing(db, 'students', 'avg_num_month TEXT');
    await _addColumnIfMissing(db, 'students', 'avg_num_1st TEXT');
    await _addColumnIfMissing(db, 'students', 'avg_num_2nd TEXT');
    await _addColumnIfMissing(db, 'students', 'avg_num_final TEXT');
    await _addColumnIfMissing(db, 'students', 'address_vill TEXT');
    await _addColumnIfMissing(db, 'students', 'address_po TEXT');
    await _addColumnIfMissing(db, 'students', 'address_ps TEXT');
    await _addColumnIfMissing(db, 'students', 'address_dist TEXT');
    final raw = await rootBundle.loadString('assets/Data_basic.json');
    final maps = await Isolate.run(() => Student.parseJsonToMaps(raw));
    final batch = db.batch();
    for (final student in maps) {
      final dakhila = student['dakhila'] as String? ?? '';
      if (dakhila.isEmpty) continue;
      final hasValue = const [
        'avg_num_month',
        'avg_num_1st',
        'avg_num_2nd',
        'avg_num_final',
        'address_vill',
        'address_po',
        'address_ps',
        'address_dist',
      ].any((k) => (student[k] as String? ?? '').isNotEmpty);
      if (!hasValue) continue;
      batch.update(
          'students',
          {
            'avg_num_month': student['avg_num_month'],
            'avg_num_1st': student['avg_num_1st'],
            'avg_num_2nd': student['avg_num_2nd'],
            'avg_num_final': student['avg_num_final'],
            'address_vill': student['address_vill'],
            'address_po': student['address_po'],
            'address_ps': student['address_ps'],
            'address_dist': student['address_dist'],
          },
          where: 'dakhila = ?',
          whereArgs: [dakhila]);
    }
    await batch.commit(noResult: true);
  }

  /// শিক্ষক-তালিকা টেবিল — (class_name, forik) natural key সহ
  /// (একই ক্লাস+ফরিকে একটাই শিক্ষক; forik খালি = পুরো ক্লাস)।
  Future _createTeachersTable(Database db) async {
    await db.execute('''
    CREATE TABLE IF NOT EXISTS teachers(
      class_name TEXT NOT NULL,
      forik TEXT NOT NULL DEFAULT '',
      name_bn TEXT,
      name_en TEXT,
      mobile TEXT,
      PRIMARY KEY(class_name, forik)
    )
    ''');
  }

  /// bundled xlsx থেকে শিক্ষক-তালিকা ভরে (পুরনো এন্ট্রি অক্ষত রাখে)।
  /// রিটার্ন: টেবিলে মোট শিক্ষক সংখ্যা।
  Future<int> _seedTeachersFromAsset(Database db) async {
    try {
      final data = await rootBundle.load(TeacherDirectory.assetPath);
      final bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      final teachers =
          await Isolate.run(() => TeacherDirectory.parseFromBytes(bytes));
      final batch = db.batch();
      for (final t in teachers) {
        batch.insert('teachers', t.toMap(),
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      await batch.commit(noResult: true);
    } catch (e) {
      debugPrint('Teacher seed failed: $e');
    }
    final count = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM teachers')) ??
        0;
    return count;
  }

  /// সব শিক্ষক — **ক্লাস লেভেল (শিক্ষা-ক্রম) অনুযায়ী সিরিয়াল**:
  /// students-এর class_level থেকে ক্লাসের সর্বনিম্ন লেভেল নিয়ে সাজানো
  /// (ক্লাস-ড্রপডাউনের একই নিয়ম)। লেভেল নেই বা ছাত্র-ডেটায় ক্লাসটাই নেই
  /// এমন শিক্ষক সবার শেষে (নাম-ক্রমে); একই ক্লাসে ফরিক সংখ্যা-ক্রমে।
  Future<List<TeacherInfo>> getTeachers() async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT t.*,
             (SELECT MIN(CAST(NULLIF(s.class_level, '') AS INTEGER))
                FROM students s
               WHERE s.class_name = t.class_name) AS level_order
      FROM teachers t
      ORDER BY level_order IS NULL ASC,
               level_order ASC,
               t.class_name COLLATE NOCASE ASC,
               CAST(NULLIF(t.forik, '') AS INTEGER) ASC,
               t.forik ASC
    ''');
    return maps.map(TeacherInfo.fromMap).toList();
  }

  /// শিক্ষক যোগ/সম্পাদনা — (class_name, forik) কী-তে replace।
  Future<bool> upsertTeacher(TeacherInfo t) async {
    try {
      final db = await database;
      await db.insert('teachers', t.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
      return true;
    } catch (e) {
      debugPrint('upsertTeacher failed: $e');
      return false;
    }
  }

  /// শিক্ষক মুছে ফেলা — রিটার্ন: মুছে ফেলা রো সংখ্যা।
  Future<int> deleteTeacher(String className, String forik) async {
    final db = await database;
    return await db.delete('teachers',
        where: 'class_name = ? AND forik = ?', whereArgs: [className, forik]);
  }

  /// শিক্ষক-তালিকা মুছে bundled xlsx থেকে নতুন করে সিড (Settings-এর সেফটি নেট)।
  /// রিটার্ন: পুনরুদ্ধারের পরে মোট শিক্ষক সংখ্যা।
  Future<int> restoreTeacherSeed() async {
    final db = await database;
    await db.delete('teachers');
    return await _seedTeachersFromAsset(db);
  }

  /// কেস নোট টেবিল — আলাদা টেবিল বলে JSON/Excel ইমপোর্টে হারায় না।
  Future _createCaseNotesTable(Database db) async {
    await db.execute('''
    CREATE TABLE IF NOT EXISTS case_notes(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      dakhila TEXT NOT NULL,
      note_date TEXT NOT NULL,
      category TEXT,
      title TEXT,
      details TEXT NOT NULL,
      created_at TEXT,
      updated_at TEXT
    )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_case_notes_dakhila ON case_notes(dakhila)');
  }

  /// এক ছাত্রের সব কেস নোট (সর্বশেষ তৈরি আগে)।
  Future<List<CaseNote>> getCaseNotes(String dakhila) async {
    final db = await database;
    final rows = await db.query('case_notes',
        where: 'dakhila = ?', whereArgs: [dakhila], orderBy: 'created_at DESC');
    return rows.map(CaseNote.fromRow).toList();
  }

  /// সব কেস নোট (provider-এর কেন্দ্রীয় ক্যাশের জন্য)।
  Future<List<CaseNote>> getAllCaseNotes() async {
    final db = await database;
    final rows = await db.query('case_notes', orderBy: 'created_at DESC');
    return rows.map(CaseNote.fromRow).toList();
  }

  /// কেস নোট যোগ/সম্পাদনা (id থাকলে সেই রো replace)।
  Future<bool> upsertCaseNote(CaseNote note) async {
    try {
      final db = await database;
      await db.insert('case_notes', note.toRow(),
          conflictAlgorithm: ConflictAlgorithm.replace);
      return true;
    } catch (e) {
      debugPrint('upsertCaseNote failed: $e');
      return false;
    }
  }

  /// কেস নোট মুছে ফেলা — রিটার্ন: মুছে ফেলা রো সংখ্যা।
  Future<int> deleteCaseNote(int id) async {
    final db = await database;
    return await db.delete('case_notes', where: 'id = ?', whereArgs: [id]);
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

  /// দাখিলা দিয়ে এক ছাত্র (সম্পাদনার আগে-পরে তুলনার জন্য)।
  Future<Student?> getStudentByDakhila(String dakhila) async {
    final db = await database;
    final maps = await db.query('students',
        where: 'dakhila = ?', whereArgs: [dakhila], limit: 1);
    return maps.isEmpty ? null : _mapToStudent(maps.first);
  }

  /// এক ছাত্রের সব ডকুমেন্ট — ক্লাস/ফরিক বদলে ফাইল-মুভের জন্য।
  Future<List<StudentDocument>> getStudentDocuments(String dakhila) async {
    final db = await database;
    final rows =
        await db.query('documents', where: 'dakhila = ?', whereArgs: [dakhila]);
    return rows.map(StudentDocument.fromRow).toList();
  }

  /// স্তর ২: ক্লাস/ফরিক বদলানোর পরে এক ট্রানজেকশনে students রো
  /// (নতুন ক্লাস/ফরিক/লেভেল + নতুন image_path) ও documents পাথ আপডেট।
  Future<bool> applyStudentMove({
    required Student updated,
    required Map<int, String> docIdToNewPath,
    required String? newImagePath,
  }) async {
    final db = await database;
    try {
      await db.transaction((txn) async {
        for (final e in docIdToNewPath.entries) {
          await txn.update('documents', {'file_path': e.value},
              where: 'id = ?', whereArgs: [e.key]);
        }
        // is_edited: 1 — কাস্টম ইমপোর্টে এই রেকর্ডের সম্পাদনা সংরক্ষিত থাকবে (স্তর ৬)
        await txn.update('students', {...updated.toMap(), 'is_edited': 1},
            where: 'dakhila = ?', whereArgs: [updated.dakhila]);
      });
      return true;
    } catch (e) {
      debugPrint('applyStudentMove failed: $e');
      return false;
    }
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

  /// সরল ইনসার্ট-সহায়ক (টেস্ট/সিড): ext ও mime পাথ থেকে অনুমিত করে।
  Future<void> insertDocument(
      String dakhila, String type, String path) async {
    final dot = path.lastIndexOf('.');
    final ext = dot >= 0 ? path.substring(dot + 1).toLowerCase() : 'jpg';
    final doc = StudentDocument(
      dakhila: dakhila,
      type: DocType.values.firstWhere(
          (t) => t.name == type.toUpperCase(),
          orElse: () => DocType.PHOTO),
      filePath: path,
      ext: ext,
      mimeType: StudentDocument.mimeTypeForExt(ext),
    );
    await upsertDocument(doc);
  }

  /// নির্দিষ্ট দাখিলার সব ডকুমেন্ট (টেস্ট/যাচাই-বান্ধব)।
  Future<List<StudentDocument>> getDocuments(String dakhila) async {
    final db = await database;
    final rows = await db.query('documents', where: 'dakhila = ?',
        whereArgs: [dakhila]);
    return rows.map(StudentDocument.fromRow).toList();
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

  /// স্তর ১ সম্পাদনা: নিরাপদ ফিল্ড (নাম/পিতা/মোবাইল/ঠিকানা/নম্বর/বছর) আপডেট।
  /// [values] DB-স্কিমা কী (stu_name, father_name, ...) নেয়; দাখিলা বদলায় না।
  /// `is_edited` ফ্ল্যাগ বসায় — কাস্টম ইমপোর্টে সম্পাদনা সংরক্ষিত হয় (স্তর ৬)।
  Future<void> updateStudentInfo(
      String dakhila, Map<String, dynamic> values) async {
    final db = await database;
    await db.update(
      'students',
      {...values, 'is_edited': 1},
      where: 'dakhila = ?',
      whereArgs: [dakhila],
    );
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
    String where =
        "(dakhila LIKE ? ESCAPE '\\' OR stu_name LIKE ? ESCAPE '\\')";
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

  /// স্তর ৬: কাস্টম ইমপোর্টে অ্যাপে সম্পাদিত (is_edited=1) রেকর্ডের
  /// যে কলামগুলো ইমপোর্টের বদলে সংরক্ষিত থাকে। ক্লাস/ফরিকসহ — নইলে
  /// সম্পাদনার পরে ফাইল নতুন ফোল্ডারে থাকা অবস্থায় ডেটা পুরনো হয়ে যেত।
  static const List<String> _preservedEditableCols = [
    'stu_name',
    'father_name',
    'mother_name',
    'guardian_mobile',
    'dakhila_year',
    'class_name',
    'forik_no',
    'class_level',
    'marhala',
    'exam_year',
    'birth_date',
    'birth_certificate_no',
    'avg_num_month',
    'avg_num_1st',
    'avg_num_2nd',
    'avg_num_final',
    'address_vill',
    'address_po',
    'address_ps',
    'address_dist',
  ];

  /// নামের ইংরেজি/আরবী রূপ — বান্ডেল ডেটায় এসব কলাম কখনো আসে না বলে
  /// কাস্টম ইমপোর্টে is_edited নির্বিশেষেই সংরক্ষিত থাকে (replaceAllStudents)।
  static const List<String> _preservedNameCols = [
    'stu_name_en',
    'stu_name_ar',
    'father_name_en',
    'father_name_ar',
    'mother_name_en',
    'mother_name_ar',
  ];

  ///
  /// Phase 1 (H2 collision-গার্ড): সংরক্ষণ যাচাইকৃত — পুরনো ও নতুন রেকর্ডের
  /// `dakhila_year`/`exam_year` **হুবহু মিললে** কেবল তখনই capture/edited/ডক
  /// প্রিজার্ভ হয়। একই দাখিলা কিন্তু ভিন্ন বছর (নতুন ব্যাচ) = ভিন্ন ব্যক্তি —
  /// আগের ছাত্রের ছবি/সম্পাদনা আর নতুন ছাত্রের নামে বসবে না।
  /// `preserveCaptures: false` দিলে সম্পূর্ণ তাজা ইমপোর্ট (কিছুই বহন নয়)।
  Future<ReplaceReport> replaceAllStudents(List<Map<String, dynamic>> maps,
      {bool preserveCaptures = true}) async {
    final db = await database;
    final report = ReplaceReport();
    await db.transaction((txn) async {
      final old = await txn.query('students', columns: [
        'dakhila',
        'image_path',
        'is_captured',
        'is_edited',
        'dakhila_year',
        'exam_year',
        ..._preservedEditableCols,
        ..._preservedNameCols,
      ]);
      String yearsOf(Map<String, dynamic> r) =>
          '${r['dakhila_year'] ?? ''}|${r['exam_year'] ?? ''}';

      final captureByDakhila = <String, (String, String?)>{
        for (final r in old)
          if ((r['is_captured'] as int?) == 1)
            (r['dakhila'] as String? ?? ''): (
              yearsOf(r),
              r['image_path'] as String?,
            ),
      };
      final editedByDakhila = <String, (String, Map<String, dynamic>)>{
        for (final r in old)
          if ((r['is_edited'] as int?) == 1)
            (r['dakhila'] as String? ?? ''): (yearsOf(r), r),
      };
      final namesByDakhila = <String, (String, Map<String, dynamic>)>{
        for (final r in old)
          (r['dakhila'] as String? ?? ''): (
            yearsOf(r),
            {
              for (final col in _preservedNameCols) col: r[col],
            }
          ),
      };
      // ইন্টিগ্রিটি ফিক্স: FK cascade চালু থাকায় students মুছলে documents rows-ও
      // মুছে যেত — তাই আগে স্ন্যাপশট নিয়ে নতুন ছাত্র বসানোর পরে ফিরিয়ে বসানো
      // হয় (নতুন ডেটায় যাদের দাখিলা আছে কেবল তাদের ডক)।
      final docRows = await txn.query('documents');
      await txn.delete('students');
      final batch = txn.batch();
      for (final source in maps) {
        final m = Map<String, dynamic>.from(source);
        final dakhila = m['dakhila'] as String? ?? '';
        final newYears = '${m['dakhila_year'] ?? ''}|${m['exam_year'] ?? ''}';
        // H2: capture প্রিজার্ভ — শুধুমাত্র বছর-জোড়া হুবহু মিললে
        if (preserveCaptures && captureByDakhila.containsKey(dakhila)) {
          final (oldYears, oldPath) = captureByDakhila[dakhila]!;
          if (oldYears == newYears) {
            m['image_path'] = oldPath;
            m['is_captured'] = 1;
          } else {
            report.collisions.add(dakhila);
          }
        }
        final edited = editedByDakhila[dakhila];
        if (edited != null && edited.$1 == newYears) {
          for (final col in _preservedEditableCols) {
            final oldV = edited.$2[col];
            if (oldV is String && oldV.isNotEmpty) m[col] = oldV;
          }
          m['is_edited'] = 1;
        }
        final oldNames = namesByDakhila[dakhila];
        if (oldNames != null && oldNames.$1 == newYears) {
          for (final col in _preservedNameCols) {
            final v = oldNames.$2[col] as String?;
            if (v != null && v.isNotEmpty && (m[col] as String? ?? '').isEmpty) {
              m[col] = v;
            }
          }
        }
        batch.insert('students', m,
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
      // documents পুনঃস্থাপন — নতুন ডেটায় যাদের দাখিলা আছে কেবল তাদের ডক;
      // H2: বছর-মিল না হলে ডক-স্লটও নতুন ছাত্রের নামে বসবে না।
      final keptDakhilas = <String>{
        for (final m in maps) (m['dakhila'] as String? ?? ''),
      };
      // H2: পুরনো বছর-জোড়া একবারই ম্যাপে তুলি (লুপে লুপ নয়)
      final oldYearsByDakhila = <String, String>{
        for (final r in old)
          (r['dakhila'] as String? ?? ''): yearsOf(r),
      };
      final docBatch = txn.batch();
      for (final r in docRows) {
        final d = (r['dakhila'] as String?) ?? '';
        if (d.isEmpty || !keptDakhilas.contains(d)) continue;
        if (preserveCaptures && oldYearsByDakhila.containsKey(d)) {
          final newM = maps.firstWhere(
            (m) => (m['dakhila'] as String? ?? '') == d,
            orElse: () => const {},
          );
          final newYears = '${newM['dakhila_year'] ?? ''}|${newM['exam_year'] ?? ''}';
          if (oldYearsByDakhila[d] != newYears) {
            continue; // ভিন্ন বছর = ভিন্ন ব্যক্তি — ডক স্লট বহন নয়
          }
        }
        docBatch.insert('documents', r,
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await docBatch.commit(noResult: true);
      // নতুন ডেটায় নেই এমন দাখিলার documents বাদ + total_docs recalc
      await txn.execute(
          'DELETE FROM documents WHERE dakhila NOT IN (SELECT dakhila FROM students)');
      await txn.execute(
          'UPDATE students SET total_docs = (SELECT COUNT(*) FROM documents '
          'WHERE documents.dakhila = students.dakhila)');
      report.imported = maps.length;
    });
    return report;
  }

  /// সব রেকর্ড মুছে ফেলে — পরের load()-এ বান্ডেল ডেটা আবার ইমপোর্ট হবে।
  /// ইন্টিগ্রিটি ফিক্স: documents টেবিলও সাফ হয় — আগে শুধু students মোছা হতো,
  /// তাই "ডাটা রিসেট"-এর পর বান্ডেল ডেটা ফিরে এলেও পুরনো ডকুমেন্ট (PHOTO/BIRTH/
  /// FORM) স্লট আবার যুক্ত হয়ে যেত; bundled-ডেটায় না-থাকা দাখিলার rows অনাথ
  /// পড়ে থাকত। ফাইলগুলো ডিস্কে (v2 ফোল্ডারে) অক্ষত থাকে — ব্যাকআপ/রিস্টোর
  /// দিয়ে ফিরিয়ে আনা যায়।
  Future<void> deleteAllStudents() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('documents');
      await txn.delete('students');
    });
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
      motherName: (m['mother_name'] as String?) ?? '',
      birthDate: (m['birth_date'] as String?) ?? '',
      birthCertNo: (m['birth_certificate_no'] as String?) ?? '',
      avgMonth: (m['avg_num_month'] as String?) ?? '',
      avg1st: (m['avg_num_1st'] as String?) ?? '',
      avg2nd: (m['avg_num_2nd'] as String?) ?? '',
      avgFinal: (m['avg_num_final'] as String?) ?? '',
      addressVill: (m['address_vill'] as String?) ?? '',
      addressPo: (m['address_po'] as String?) ?? '',
      addressPs: (m['address_ps'] as String?) ?? '',
      addressDist: (m['address_dist'] as String?) ?? '',
      stuNameEn: (m['stu_name_en'] as String?) ?? '',
      stuNameAr: (m['stu_name_ar'] as String?) ?? '',
      fatherNameEn: (m['father_name_en'] as String?) ?? '',
      fatherNameAr: (m['father_name_ar'] as String?) ?? '',
      motherNameEn: (m['mother_name_en'] as String?) ?? '',
      motherNameAr: (m['mother_name_ar'] as String?) ?? '',
      imagePath: m['image_path'] as String?,
      isCaptured: (m['is_captured'] as int?) ?? 0,
      totalDocs: (m['total_docs'] as int?) ?? 0,
    );
  }

  /// Excel রাউন্ড-ট্রিপ: অ-খালি সেল-মান দিয়ে বহু ছাত্র আপডেট
  /// (is_edited=1 — কাস্টম ইমপোর্টে সংরক্ষিত)। দাখিলা মিলে গেলেই আপডেট;
  /// রিটার্ন: সত্যিই মিলে যাওয়া (আপডেট হওয়া) ছাত্র-সংখ্যা।
  Future<int> bulkApplyStudentUpdates(
      List<({String dakhila, Map<String, dynamic> values})> updates) async {
    final db = await database;
    var applied = 0;
    await db.transaction((txn) async {
      for (final u in updates) {
        applied += await txn.update(
          'students',
          {...u.values, 'is_edited': 1},
          where: 'dakhila = ?',
          whereArgs: [u.dakhila],
        );
      }
    });
    return applied;
  }

  /// ব্যাচ নাম-ক্ষেত্র আপডেট + নাম-ক্যাশ সারি — এক ট্রানজেকশনে (হাজার খানেক
  /// রেকর্ডেও দ্রুত)। বিদ্যমান En/Ar মান খালি হলেই লেখা হয়; is_edited=1 বসে।
  /// রিটার্ন: আপডেট হওয়া ছাত্র-সংখ্যা।
  Future<int> bulkSaveNameFields(
    List<({String dakhila, String en, String ar})> updates,
    List<({String key, String en, String ar})> cacheRows,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final u in updates) {
        batch.update(
          'students',
          {
            if (u.en.isNotEmpty) 'stu_name_en': u.en,
            if (u.ar.isNotEmpty) 'stu_name_ar': u.ar,
            'is_edited': 1,
          },
          where: 'dakhila = ?',
          whereArgs: [u.dakhila],
        );
      }
      final now = DateTime.now().toIso8601String();
      for (final c in cacheRows) {
        batch.insert(
          'name_cache',
          {
            'bangla': c.key,
            'english': c.en,
            'arabic': c.ar,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
    return updates.length;
  }

  /// নাম-ক্যাশ খোঁজা — আগে নিশ্চিত করা (বাংলা → ইংরেজি, আরবী) জোড়া।
  /// [bangla] = স্বাভাবিকীকৃত ক্যাশ-কী (NameTransliterator.cacheKey)।
  Future<({String english, String arabic})?> lookupNameCache(
      String bangla) async {
    final db = await database;
    final rows = await db.query(
      'name_cache',
      columns: ['english', 'arabic'],
      where: 'bangla = ?',
      whereArgs: [bangla],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return (
      english: (rows.first['english'] as String?) ?? '',
      arabic: (rows.first['arabic'] as String?) ?? '',
    );
  }

  /// নিশ্চিত করা নাম-জোড়া ক্যাশে রাখা (INSERT OR REPLACE —
  /// একই বাংলা নামের আগের মান হালনাগাদ হয়)।
  Future<void> saveNameCache(
      String bangla, String english, String arabic) async {
    final db = await database;
    await db.insert(
      'name_cache',
      {
        'bangla': bangla,
        'english': english,
        'arabic': arabic,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
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
