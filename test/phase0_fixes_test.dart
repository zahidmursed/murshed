import 'dart:io';

import 'package:dakhila_camera/db/database_helper.dart';
import 'package:dakhila_camera/models/document.dart';
import 'package:dakhila_camera/providers/student_provider.dart';
import 'package:dakhila_camera/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Phase 0 রিলিজ-ব্লকার রিগ্রেশন:
/// C1 — ক্লাস/ফরিক বদলালে ২০টি কলাম নীরবে মুছে যেত (ডেটা লস)
/// H1 — "ডাটা রিসেট"-এ documents সাফ হতো না + total_docs stale
/// FK — documents → students ON DELETE CASCADE কার্যকর (orphan প্রতিরোধ)
/// H3 — PHOTO ডক/ফাইল আছে কিন্তু is_captured=0 — সেলফ-হিল দুই-মুখী
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  /// সব সম্পাদনাযোগ্য কলাম-সহ একটি সম্পূর্ণ ছাত্র-ম্যাপ (C1 টেস্টের ভিত্তি)।
  const fullStudent = <String, dynamic>{
    'dakhila': '901',
    'stu_name': 'রহিম',
    'class_name': 'মিশকাত',
    'forik_no': '1',
    'father_name': 'আব্দুল করিম',
    'guardian_mobile': '01712345678',
    'dakhila_year': '2026',
    'class_level': '7',
    'marhala': 'মিশকাত',
    'exam_year': '2026',
    'mother_name': 'মা-বেগম',
    'birth_date': '01-01-2010',
    'birth_certificate_no': '1234567890',
    'avg_num_month': '81',
    'avg_num_1st': '75.5',
    'avg_num_2nd': '79',
    'avg_num_final': '84',
    'address_vill': 'গ্রাম-ক',
    'address_po': 'ডাকঘর-খ',
    'address_ps': 'থানা-গ',
    'address_dist': 'জেলা-ঘ',
    'stu_name_en': 'Rahim',
    'stu_name_ar': 'رحيم',
    'father_name_en': 'Abdul Karim',
    'father_name_ar': 'عبد الكريم',
    'mother_name_en': 'Ma Begum',
    'mother_name_ar': 'ام',
  };

  Future<StudentProvider> setup(String prefix) async {
    final dbDir = await Directory.systemTemp.createTemp('${prefix}_db');
    final storeDir = await Directory.systemTemp.createTemp('${prefix}_store');
    addTearDown(() async {
      await DatabaseHelper.instance.resetForTest();
      StorageService.testBaseDir = null;
      if (await dbDir.exists()) await dbDir.delete(recursive: true);
      if (await storeDir.exists()) await storeDir.delete(recursive: true);
    });
    await databaseFactory.setDatabasesPath(dbDir.path);
    StorageService.testBaseDir = storeDir;
    return StudentProvider();
  }

  test('C1: class/forik বদলালেও সব এডিট-ফিল্ড অক্ষত থাকে (ডেটা-লস ফিক্স)',
      () async {
    final provider = await setup('p0_c1');
    final db = DatabaseHelper.instance;
    await db.replaceAllStudents([Map<String, dynamic>.from(fullStudent)]);

    await provider.load();
    final before = (await db.getStudentByDakhila('901'))!;
    // প্রি-কন্ডিশন: মানগুলো সত্যিই DB-তে আছে
    expect(before.motherName, 'মা-বেগম');
    expect(before.avgFinal, '84');

    // ক্লাস+ফরিক বদল — এখানেই আগে ২০টি কলাম মুছে যেত
    final updated = before.copyWith(
      className: 'নতুন-ক্লাস',
      forikNo: '2',
      stuName: 'রহিম মাহমুদ',
    );
    final res = await provider.editStudentIdentity(updated);
    expect(res.ok, isTrue);

    final after = (await db.getStudentByDakhila('901'))!;
    // যা বদলানো হয়েছে
    expect(after.className, 'নতুন-ক্লাস');
    expect(after.forikNo, '2');
    expect(after.stuName, 'রহিম মাহমুদ');
    // যা বদলানো হয়নি — একটাও হারানো চলবে না
    expect(after.fatherName, 'আব্দুল করিম');
    expect(after.guardianMobile, '01712345678');
    expect(after.motherName, 'মা-বেগম');
    expect(after.birthDate, '01-01-2010');
    expect(after.birthCertNo, '1234567890');
    expect(after.marhala, 'মিশকাত');
    expect(after.examYear, '2026');
    expect(after.dakhilaYear, '2026');
    expect(after.classLevel, '7');
    expect(after.avgMonth, '81');
    expect(after.avg1st, '75.5');
    expect(after.avg2nd, '79');
    expect(after.avgFinal, '84');
    expect(after.addressVill, 'গ্রাম-ক');
    expect(after.addressPo, 'ডাকঘর-খ');
    expect(after.addressPs, 'থানা-গ');
    expect(after.addressDist, 'জেলা-ঘ');
    expect(after.stuNameEn, 'Rahim');
    expect(after.stuNameAr, 'رحيم');
    expect(after.fatherNameEn, 'Abdul Karim');
    expect(after.fatherNameAr, 'عبد الكريم');
    expect(after.motherNameEn, 'Ma Begum');
    expect(after.motherNameAr, 'ام');
    // মেমোরি-কপিও হালনাগাদ
    expect(provider.findStudent('901')!.motherName, 'মা-বেগম');
  });

  test('H1: ডাটা রিসেটে documents সাফ হয় ও total_docs stale থাকে না', () async {
    final provider = await setup('p0_h1');
    final db = DatabaseHelper.instance;
    await db.replaceAllStudents([Map<String, dynamic>.from(fullStudent)]);

    final photoPath = '${StorageService.testBaseDir!.path}/901.jpg';
    await File(photoPath).writeAsBytes(const [1, 2, 3, 4]);
    await db.updateImage('901', photoPath);
    await db.upsertDocument(StudentDocument(
      dakhila: '901',
      type: DocType.BIRTH,
      filePath: '${StorageService.testBaseDir!.path}/901_BIRTH.jpg',
      ext: 'jpg',
      status: 1,
    ));
    expect((await db.getAllDocumentsMap())['901']!.length, 2);
    expect((await db.getStudentByDakhila('901'))!.totalDocs, 2);

    await db.deleteAllStudents();

    expect(await db.getAllStudents(), isEmpty);
    // আগে এখানে পুরনো documents থেকে যেত → পরের ইমপোর্টে "মুছে ফেলা" ডক ফিরে আসত
    expect(await db.getAllDocumentsMap(), isEmpty);

    // রিসেটের পর বান্ডেল/কাস্টম ইমপোর্ট: total_docs 0-ই থাকা চাই
    await db.replaceAllStudents([Map<String, dynamic>.from(fullStudent)]);
    expect((await db.getStudentByDakhila('901'))!.totalDocs, 0);
    await provider.load();
    expect(provider.docOf('901', DocType.PHOTO), isNull);
    expect(provider.docOf('901', DocType.BIRTH), isNull);
  });

  test('H1b: অজানা দাখিলার ডকুমেন্ট লেখা যায় না (FK enforcement চালু)',
      () async {
    await setup('p0_fk');
    final db = DatabaseHelper.instance;
    await expectLater(
      db.upsertDocument(const StudentDocument(
        dakhila: 'নেই-এমন-দাখিলা',
        type: DocType.FORM,
        filePath: '/tmp/none.pdf',
        ext: 'pdf',
        status: 1,
      )),
      throwsA(anything),
    );
  });

  test('H1c: কাস্টম ইমপোর্টে বেঁচে থাকা ছাত্রের ডক স্লট অক্ষত থাকে', () async {
    final provider = await setup('p0_h1c');
    final db = DatabaseHelper.instance;
    await db.replaceAllStudents([Map<String, dynamic>.from(fullStudent)]);
    final photoPath = '${StorageService.testBaseDir!.path}/901.jpg';
    await File(photoPath).writeAsBytes(const [1, 2, 3]);
    await db.updateImage('901', photoPath);

    // নতুন ইমপোর্ট: 901 আছে, 902 নতুন
    await db.replaceAllStudents([
      {...Map<String, dynamic>.from(fullStudent), 'stu_name': 'ইমপোর্ট নাম'},
      {
        'dakhila': '902',
        'stu_name': 'নতুন ছাত্র',
        'class_name': 'মিশকাত',
        'forik_no': '1',
        'dakhila_year': '2026',
      },
    ]);

    final docs = await db.getAllDocumentsMap();
    expect(docs['901']?[DocType.PHOTO], isNotNull);
    expect(docs['901']![DocType.PHOTO]!.filePath, photoPath);
    final s901 = (await db.getStudentByDakhila('901'))!;
    expect(s901.isCaptured, 1);
    expect(s901.totalDocs, 1);
    await provider.load();
    expect(provider.captured, 1);
  });

  test('H3: PHOTO ডক/ফাইল আছে কিন্তু is_captured=0 → load()-এ heal হয়',
      () async {
    final provider = await setup('p0_h3');
    final db = DatabaseHelper.instance;
    await db.replaceAllStudents([Map<String, dynamic>.from(fullStudent)]);

    // v2 পাথে আসল ফাইল, কিন্তু students.image_path খালি ও is_captured=0
    final path = await StorageService.documentPath(
        'মিশকাত', '1', '901', DocType.PHOTO, 'jpg');
    await File(path).writeAsBytes(const [9, 8, 7, 6]);
    await db.upsertDocument(StudentDocument(
      dakhila: '901',
      type: DocType.PHOTO,
      filePath: path,
      ext: 'jpg',
      mimeType: 'image/jpeg',
      status: 1,
    ));
    final stale = (await db.getStudentByDakhila('901'))!;
    expect(stale.isCaptured, 0);
    expect(stale.imagePath, isNull);

    await provider.load();

    final healed = (await db.getStudentByDakhila('901'))!;
    expect(healed.isCaptured, 1);
    expect(healed.imagePath, path);
    expect(provider.findStudent('901')!.isCaptured, 1);
    expect(provider.captured, 1); // হেডারের "তোলা" হিসাব এখন সঠিক
  });

  test('H3b: ফাইল কোথাও না থাকলে heal কিছু মোছে না (repair-only)', () async {
    final provider = await setup('p0_h3b');
    final db = DatabaseHelper.instance;
    await db.replaceAllStudents([Map<String, dynamic>.from(fullStudent)]);

    // রেকর্ড আছে, ফাইল নেই — হারানো ফাইল ধরে কিছুই বদলানো/মোছা যাবে না
    await db.updateImage('901', '/nonexistent/901.jpg');
    await provider.load();

    final s = (await db.getStudentByDakhila('901'))!;
    expect(s.isCaptured, 1);
    expect(s.imagePath, '/nonexistent/901.jpg');
    // ভুয়া PHOTO ডকও বানানো হয়নি
    expect((await db.getAllDocumentsMap())['901']!.length, 1);
  });
}