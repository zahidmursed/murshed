import 'dart:io';

import 'package:dakhila_camera/db/database_helper.dart';
import 'package:dakhila_camera/models/case_note.dart';
import 'package:dakhila_camera/providers/case_notes_provider.dart';
import 'package:dakhila_camera/services/case_notes_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('PIN service: set/verify/remove roundtrip (hash stored)', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await CaseNotesService.isPinSet(), isFalse);

    await CaseNotesService.setPin('1234');
    expect(await CaseNotesService.isPinSet(), isTrue);
    expect(await CaseNotesService.verifyPin('1234'), isTrue);
    expect(await CaseNotesService.verifyPin('9999'), isFalse);
    // সরাসরি পিন নয় — hash সংরক্ষিত
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('caseNotesPinHash'), isNot('1234'));

    await CaseNotesService.removePin();
    expect(await CaseNotesService.isPinSet(), isFalse);
    expect(await CaseNotesService.verifyPin('1234'), isFalse);
  });

  test('case notes CRUD works and survives student re-import', () async {
    final tmpDir = await Directory.systemTemp.createTemp('case_notes_db');
    addTearDown(() async {
      await DatabaseHelper.instance.resetForTest();
      if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
    });
    await databaseFactory.setDatabasesPath(tmpDir.path);
    await DatabaseHelper.instance.replaceAllStudents([
      {
        'dakhila': '281',
        'stu_name': 'রাসেল',
        'class_name': 'ইফতা',
        'dakhila_year': '2026',
      },
    ]);

    // দুটি নোট 281-এর জন্য, একটি 282-এর জন্য
    final ok1 = await DatabaseHelper.instance.upsertCaseNote(const CaseNote(
      dakhila: '281',
      noteDate: '01-09-2026',
      category: 'শৃঙ্খলা',
      title: 'ক্লাসে দেরি',
      details: 'সকালে ৩০ মিনিট দেরিতে এসেছে।',
    ));
    expect(ok1, isTrue);
    await DatabaseHelper.instance.upsertCaseNote(const CaseNote(
      dakhila: '281',
      noteDate: '05-09-2026',
      category: 'মামলা',
      title: 'বাইরে বিবাদ',
      details: 'বাইরে স্থানীয় ছেলেদের সাথে বিবাদে জড়িয়েছে।',
    ));
    await DatabaseHelper.instance.upsertCaseNote(const CaseNote(
      dakhila: '282',
      noteDate: '02-09-2026',
      category: 'অনুপস্থিতি',
      title: 'তিন দিন অনুপস্থিত',
      details: 'গত তিন দিন ক্লাসে আসেনি।',
    ));

    var notes281 = await DatabaseHelper.instance.getCaseNotes('281');
    expect(notes281.length, 2);
    expect(notes281.every((n) => n.dakhila == '281'), isTrue);

    // সম্পাদনা (একই id → replace)
    final first = notes281.first;
    await DatabaseHelper.instance.upsertCaseNote(CaseNote(
      id: first.id,
      dakhila: '281',
      noteDate: first.noteDate,
      category: first.category,
      title: 'ক্লাসে দেরি (হালনাগাদ)',
      details: first.details,
      createdAt: first.createdAt,
      updatedAt: DateTime.now().toIso8601String(),
    ));
    notes281 = await DatabaseHelper.instance.getCaseNotes('281');
    expect(notes281.firstWhere((n) => n.id == first.id).title,
        'ক্লাসে দেরি (হালনাগাদ)');
    // এখনো ২টি (replace, ডুপ্লিকেট নয়)
    expect(notes281.length, 2);

    // মুছে ফেলা
    final deleted =
        await DatabaseHelper.instance.deleteCaseNote(notes281.last.id!);
    expect(deleted, 1);
    expect((await DatabaseHelper.instance.getCaseNotes('281')).length, 1);

    // স্তর: কাস্টম ইমপোর্ট (students replace) — নোট টিকে থাকে
    await DatabaseHelper.instance.replaceAllStudents([
      {
        'dakhila': '281',
        'stu_name': 'রাসেল নতুন',
        'class_name': 'ইফতা',
        'dakhila_year': '2026',
      },
    ]);
    expect(
        (await DatabaseHelper.instance.getCaseNotes('281')).length, 1);
    final s = await DatabaseHelper.instance.getStudentByDakhila('281');
    expect(s!.stuName, 'রাসেল নতুন'); // ইমপোর্ট ডেটা প্রয়োগ হয়েছে
  });

  test('provider: ensureLoaded + upsert/delete reflect in memory', () async {
    final tmpDir = await Directory.systemTemp.createTemp('case_notes_prov');
    addTearDown(() async {
      await DatabaseHelper.instance.resetForTest();
      if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
    });
    await databaseFactory.setDatabasesPath(tmpDir.path);

    final provider = CaseNotesProvider();
    await provider.ensureLoaded();
    expect(provider.loaded, isTrue);

    await provider.upsert(const CaseNote(
      dakhila: '281',
      noteDate: '01-09-2026',
      category: 'শৃঙ্খলা',
      title: 'টেস্ট নোট',
      details: 'বিস্তারিত',
    ));
    expect(provider.countFor('281'), 1);
    expect(provider.notesFor('281').first.title, 'টেস্ট নোট');

    final note = provider.notesFor('281').first;
    final deleted = await provider.delete(note.id!);
    expect(deleted, isTrue);
    expect(provider.countFor('281'), 0);
  });
}
