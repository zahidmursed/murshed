import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../db/database_helper.dart';

/// ফেজ C: পূর্ণ ব্যাকআপ/রিস্টোর — DB (ছাত্র+ডক+ক্যাশ+শিক্ষক) +
/// v2 ফোল্ডার (সব ছবি/ডকুমেন্ট) + branding (লোগো) এক ZIP-এ।
/// বড় ফাইলের জন্য streaming encoder/extractor — মেমোরি নিরাপদ।
class BackupService {
  BackupService._();

  static const String _dbEntry = 'dakhila.db';
  static const String _manifestEntry = 'manifest.json';

  static Future<Directory> _defaultAppDir() async =>
      await getExternalStorageDirectory() ??
      await getApplicationDocumentsDirectory();

  /// পূর্ণ ব্যাকআপ ZIP তৈরি। [appDirPath]/[outDir] টেস্টে ওভাররাইড।
  /// রিটার্ন: ZIP ফাইল-পাথ।
  static Future<String> backup({
    required String institutionName,
    String? appDirPath,
    String? outDir,
    void Function(int done, int total)? onProgress,
  }) async {
    final dbHelper = DatabaseHelper.instance;
    // WAL-ফাইল ফ্লাশ — কপি-সামঞ্জস্যের জন্য (WAL না থাকলে no-op)
    try {
      final db = await dbHelper.database;
      await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (_) {}

    final appDir = appDirPath ?? (await _defaultAppDir()).path;
    final dbPath = await dbHelper.databaseFilePath();
    final v2Dir = Directory(p.join(appDir, 'DakhilaCamera', 'v2'));
    final brandingDir = Directory(p.join(appDir, 'DakhilaCamera', 'branding'));

    final entries = <(String, String)>[]; // (zipEntry, sourcePath)
    entries.add((_dbEntry, dbPath));
    if (await v2Dir.exists()) {
      await for (final e in v2Dir.list(recursive: true, followLinks: false)) {
        if (e is File) {
          final rel =
              p.relative(e.path, from: v2Dir.path).replaceAll('\\', '/');
          entries.add(('v2/$rel', e.path));
        }
      }
    }
    if (await brandingDir.exists()) {
      await for (final e
          in brandingDir.list(recursive: true, followLinks: false)) {
        if (e is File) {
          final rel = p
              .relative(e.path, from: brandingDir.path)
              .replaceAll('\\', '/');
          entries.add(('branding/$rel', e.path));
        }
      }
    }

    final out = outDir ?? p.join(appDir, 'Export');
    final dir = Directory(out);
    if (!await dir.exists()) await dir.create(recursive: true);
    final zipPath = p.join(dir.path, 'Backup_dakhila_${_stamp()}.zip');

    final encoder = ZipFileEncoder();
    encoder.create(zipPath);
    var done = 0;
    for (final (entry, source) in entries) {
      encoder.addFile(File(source), entry);
      done++;
      onProgress?.call(done, entries.length);
    }
    final manifest = json.encode({
      'createdAt': DateTime.now().toIso8601String(),
      'files': entries.length,
      'institutionName': institutionName,
    });
    final mBytes = utf8.encode(manifest);
    encoder
        .addArchiveFile(ArchiveFile(_manifestEntry, mBytes.length, mBytes));
    encoder.close();
    debugPrint('Backup done: $zipPath (${entries.length} entries)');
    return zipPath;
  }

  /// রিস্টোর — বিপজ্জনক: বর্তমান DB ও v2/branding ফোল্ডার ব্যাকআপের
  /// কনটেন্ট দিয়ে সম্পূর্ণ বদলে যায়। ডেটাবেস যাচাই করে বসানো হয়।
  /// কলার পরে provider.load() চালাবে (মেমোরি রিফ্রেশ)।
  static Future<({int students, int files, String? institutionName})> restore({
    required String zipPath,
    required String institutionName,
    String? appDirPath,
    void Function(String step)? onStep,
  }) async {
    final dbHelper = DatabaseHelper.instance;
    final tmp = await Directory.systemTemp.createTemp('dakhila_restore');
    try {
      onStep?.call('ব্যাকআপ ফাইল বের করা হচ্ছে...');
      await extractFileToDisk(zipPath, tmp.path);
      final dbEntry = File(p.join(tmp.path, _dbEntry));
      if (!await dbEntry.exists()) {
        throw StateError('এটা বৈধ ব্যাকআপ নয় — dakhila.db নেই');
      }

      onStep?.call('ডেটাবেস যাচাই হচ্ছে...');
      final check = await openDatabase(dbEntry.path);
      int students;
      try {
        students = Sqflite.firstIntValue(
                await check.rawQuery('SELECT COUNT(*) FROM students')) ??
            0;
      } finally {
        await check.close();
      }

      String? institutionFromManifest;
      final manifestFile = File(p.join(tmp.path, _manifestEntry));
      if (await manifestFile.exists()) {
        try {
          final m = json.decode(await manifestFile.readAsString())
              as Map<String, dynamic>;
          institutionFromManifest = m['institutionName'] as String?;
        } catch (_) {}
      }

      onStep?.call('ডেটাবেস বদলানো হচ্ছে...');
      await dbHelper.close();
      final target = await dbHelper.databaseFilePath();
      for (final suffix in ['', '-wal', '-shm', '-journal']) {
        final f = File('$target$suffix');
        if (await f.exists()) await f.delete();
      }
      await dbEntry.copy(target);

      onStep?.call('ছবি/ডকুমেন্ট বদলানো হচ্ছে...');
      final appDir = appDirPath ?? (await _defaultAppDir()).path;
      final v2Target = Directory(p.join(appDir, 'DakhilaCamera', 'v2'));
      if (await v2Target.exists()) await v2Target.delete(recursive: true);
      final v2Src = Directory(p.join(tmp.path, 'v2'));
      if (await v2Src.exists()) {
        await _copyDirectory(v2Src, v2Target);
      }

      final brandSrc = Directory(p.join(tmp.path, 'branding'));
      if (await brandSrc.exists()) {
        final brandTarget =
            Directory(p.join(appDir, 'DakhilaCamera', 'branding'));
        if (await brandTarget.exists()) {
          await brandTarget.delete(recursive: true);
        }
        await _copyDirectory(brandSrc, brandTarget);
      }

      final files = await _countFiles(v2Target);
      return (
        students: students,
        files: files,
        institutionName: institutionFromManifest ?? institutionName,
      );
    } finally {
      try {
        if (await tmp.exists()) await tmp.delete(recursive: true);
      } catch (_) {}
    }
  }

  static Future<void> _copyDirectory(Directory src, Directory dst) async {
    await dst.create(recursive: true);
    await for (final e in src.list(recursive: true, followLinks: false)) {
      final rel = p.relative(e.path, from: src.path);
      final target = p.join(dst.path, rel);
      if (e is Directory) {
        await Directory(target).create(recursive: true);
      } else if (e is File) {
        await File(target).parent.create(recursive: true);
        await e.copy(target);
      }
    }
  }

  static Future<int> _countFiles(Directory dir) async {
    if (!await dir.exists()) return 0;
    var n = 0;
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      if (e is File) n++;
    }
    return n;
  }

  static String _stamp() {
    final now = DateTime.now();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '${now.year}-$m-$d';
  }
}