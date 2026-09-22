import 'dart:io';

import 'package:dakhila_camera/db/database_helper.dart';
import 'package:dakhila_camera/models/document.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<void> openTempDb() async {
    final tmpDir = await Directory.systemTemp.createTemp('dakhila_sync_test');
    await databaseFactory.setDatabasesPath(tmpDir.path);
    addTearDown(() async {
      await DatabaseHelper.instance.resetForTest();
      if (await tmpDir.exists()) {
        await tmpDir.delete(recursive: true);
      }
    });
  }

  Future<void> seedStudents(List<String> dakhilas) async {
    await DatabaseHelper.instance.replaceAllStudents([
      for (final d in dakhilas)
        {
          'dakhila': d,
          'stu_name': 'টেস্ট ছাত্র $d',
          'class_name': 'হিফজুল কুরআন',
          'forik_no': '1',
          'father_name': 'অভিভাবক',
          'dakhila_year': '2026',
        },
    ]);
  }

  Future<void> insertDoc(String dakhila, String type, String path) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert('documents', {
      'dakhila': dakhila,
      'doc_type': type,
      'file_path': path,
      'file_ext': 'jpg',
      'mime_type': 'image/jpeg',
      'status': 1,
      'updated_at': '2026-09-19T10:00:00',
    });
  }

  test('doc sync-state lifecycle: pending → synced/failed + retry', () async {
    await openTempDb();
    await seedStudents(['554']);
    await insertDoc('554', 'PHOTO', '/tmp/554.jpg');

    final counts0 = await DatabaseHelper.instance.docSyncCounts();
    expect(counts0['pending'], 1);
    expect(counts0['total'], 1);
    expect(await DatabaseHelper.instance.countPendingDocs(), 1);

    // সফল আপলোড → synced (storage_path সহ)
    await DatabaseHelper.instance.markDocSynced(
        '554', DocType.PHOTO, 'uploads/2026/554.jpg', 'teacher@x.com');
    var counts = await DatabaseHelper.instance.docSyncCounts();
    expect(counts['synced'], 1);
    expect(counts['pending'], 0);

    // দ্বিতীয় ডক ব্যর্থ হলে failed — কিন্তু getPendingDocs আবার তাকেই দেয়
    await insertDoc('554', 'BIRTH', '/tmp/554_b.jpg');
    await DatabaseHelper.instance.markDocFailed('554', DocType.BIRTH);
    final pending = await DatabaseHelper.instance.getPendingDocs(limit: 10);
    expect(pending.map((d) => d.type.name), contains('BIRTH'));

    // skipped হলে তালিকা থেকে বাদ
    await DatabaseHelper.instance.markDocSynced(
        '554', DocType.BIRTH, 'uploads/2026/554_b.jpg', null);
    final db = await DatabaseHelper.instance.database;
    await db.update('documents', {'sync_state': 'skipped'},
        where: 'dakhila = ? AND doc_type = ?', whereArgs: ['554', 'PHOTO']);
    expect(await DatabaseHelper.instance.getPendingDocs(limit: 10), isEmpty);

    // পুরনো ছবির নিয়ম: synced নয় এমন সবকিছু → pending
    // (আগে PHOTO=skipped, BIRTH=synced ছিল → কেবল PHOTO বদলায়)
    final n = await DatabaseHelper.instance.setAllDocsSyncState(true);
    expect(n, 1);
    final counts2 = await DatabaseHelper.instance.docSyncCounts();
    expect(counts2['pending'], 1);
    expect(counts2['synced'], 1);
  });

  test('sync_log keeps only last 30 sessions', () async {
    await openTempDb();
    for (var i = 0; i < 35; i++) {
      await DatabaseHelper.instance.addSyncLog(
        startedAt: '2026-09-19T10:$i:00',
        uploaded: i,
        downloaded: 0,
        failed: 0,
        note: 't$i',
      );
    }
    final logs = await DatabaseHelper.instance.recentSyncLogs(limit: 5);
    expect(logs.length, 5);
    // নতুন আগে — সর্বশেষ সেশন প্রথমে
    expect(logs.first['note'], 't34');
    final db = await DatabaseHelper.instance.database;
    final total = (await db.rawQuery('SELECT COUNT(*) c FROM sync_log')).first;
    expect(total['c'], 30);
  });

  test('applyServerStudents: add, update, conflict (is_edited), soft-delete',
      () async {
    await openTempDb();
    await seedStudents(['554', '555']);

    // 554 লোকালে সম্পাদিত (is_edited=1) → conflict, মান চাপানো হবে না
    final db = await DatabaseHelper.instance.database;
    await db.update('students', {'is_edited': 1, 'stu_name': 'শিক্ষকের নাম'},
        where: 'dakhila = ?', whereArgs: ['554']);

    final stats = await DatabaseHelper.instance.applyServerStudents([
      {
        // নতুন — এই ফোনে ছিল না
        'dakhila': '900',
        'stu_name': 'সার্ভারে নতুন',
        'class_name': 'ইফতা',
        'updated_at': '2026-09-19 10:00:00',
      },
      {
        // বিদ্যমান, লোকালে অসম্পাদিত → আপডেট
        'dakhila': '555',
        'stu_name': 'সার্ভার আপডেট',
        'updated_at': '2026-09-19 10:05:00',
      },
      {
        // বিদ্যমান + is_edited=1 → দ্বন্দ্ব
        'dakhila': '554',
        'stu_name': 'কেন্দ্রীয় নাম',
        'updated_at': '2026-09-19 10:06:00',
      },
      {
        // সার্ভারে soft-delete → লোকালে ছোঁয়া হয় না
        'dakhila': '555',
        'deleted_at': '2026-09-19 10:07:00',
      },
    ]);
    expect(stats.added, 1);
    expect(stats.updated, 1);
    expect(stats.conflicts, 1);
    expect(stats.deactivated, 1);

    final s554 = await DatabaseHelper.instance.getStudentByDakhila('554');
    // শিক্ষকের সম্পাদনা অক্ষত
    expect(s554!.stuName, 'শিক্ষকের নাম');
    final s900 = await DatabaseHelper.instance.getStudentByDakhila('900');
    expect(s900!.stuName, 'সার্ভারে নতুন');
    // soft-delete: 555 ফোনের তালিকা থেকেও বাদ (ছবি-ফাইল ডিস্কে অক্ষত থাকে)
    final s555 = await DatabaseHelper.instance.getStudentByDakhila('555');
    expect(s555, isNull);
  });

  test('applyServerDocuments: local update + cloud_docs registry + stats',
      () async {
    await openTempDb();
    await seedStudents(['554']);
    await insertDoc('554', 'PHOTO', '/tmp/554.jpg');

    final touched = await DatabaseHelper.instance.applyServerDocuments([
      {
        // এই ফোনে আছে → storage_path/captured_by বসে
        'dakhila': '554',
        'doc_type': 'PHOTO',
        'storage_path': 'uploads/2026/554.jpg',
        'captured_by': 'teacher@x.com',
        'is_verified': '1',
      },
      {
        // এই ফোনে নেই → cloud_docs রেজিস্ট্রিতে
        'dakhila': '556',
        'doc_type': 'FORM',
        'storage_path': 'uploads/2026/556_form.jpg',
        'captured_by': 'other@x.com',
        'is_verified': '0',
      },
    ]);
    expect(touched, 2);

    final db = await DatabaseHelper.instance.database;
    final doc = await db.query('documents',
        where: 'dakhila = ? AND doc_type = ?', whereArgs: ['554', 'PHOTO']);
    expect(doc.first['storage_path'], 'uploads/2026/554.jpg');
    expect(doc.first['captured_by'], 'teacher@x.com');

    expect(await DatabaseHelper.instance.cloudDocTypesFor('556'), {'FORM'});
    final stats = await DatabaseHelper.instance.cloudDocStats();
    expect(stats['FORM'], 1);
  });
}
