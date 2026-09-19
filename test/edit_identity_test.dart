import 'dart:io';

import 'package:dakhila_camera/db/database_helper.dart';
import 'package:dakhila_camera/models/document.dart';
import 'package:dakhila_camera/providers/student_provider.dart';
import 'package:dakhila_camera/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _oldClass = 'পুরনো ক্লাস';
const _newClass = 'নতুন ক্লাস';

void _write(String path, int size) {
  final f = File(path);
  f.parent.createSync(recursive: true);
  f.writeAsBytesSync(List.filled(size, 65));
}

String _v2(String storageDir, String cls, String forik, String dakhila,
        [String type = '']) =>
    [storageDir, 'DakhilaCamera', 'v2', cls, 'Forik_$forik', dakhila, type]
        .join('/');

Future<StudentProvider> _setup(
    String prefix, Directory dbDir, Directory storeDir) async {
  await databaseFactory.setDatabasesPath(dbDir.path);
  StorageService.testBaseDir = storeDir;
  final provider = StudentProvider();
  await provider.load();
  return provider;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() {
    StorageService.testBaseDir = null;
  });

  test('class+forik change moves photo & birth files and updates DB',
      () async {
    final dbDir = await Directory.systemTemp.createTemp('ident_db');
    final storeDir = await Directory.systemTemp.createTemp('ident_store');
    addTearDown(() async {
      await DatabaseHelper.instance.resetForTest();
      StorageService.testBaseDir = null;
      if (await dbDir.exists()) await dbDir.delete(recursive: true);
      if (await storeDir.exists()) await storeDir.delete(recursive: true);
    });
    final provider = await _setup('ident1', dbDir, storeDir);

    await DatabaseHelper.instance.replaceAllStudents([
      {
        'dakhila': '281',
        'stu_name': 'রাসেল',
        'class_name': _oldClass,
        'forik_no': '1',
        'dakhila_year': '2026',
      },
      {
        'dakhila': '282',
        'stu_name': 'রহিম',
        'class_name': _oldClass,
        'forik_no': '1',
        'dakhila_year': '2026',
      },
    ]);

    // 281-এর পুরনো PHOTO + BIRTH ফাইল
    final oldPhotoPath =
        '${_v2(storeDir.path, _oldClass, '1', '281', 'PHOTO')}/281.jpg';
    final oldBirthPath =
        '${_v2(storeDir.path, _oldClass, '1', '281', 'BIRTH')}/281.jpg';
    _write(oldPhotoPath, 120);
    _write(oldBirthPath, 80);
    await DatabaseHelper.instance.updateImage('281', oldPhotoPath);
    await DatabaseHelper.instance.upsertDocument(StudentDocument(
      dakhila: '281',
      type: DocType.BIRTH,
      filePath: oldBirthPath,
      ext: 'jpg',
      status: 1,
    ));
    // 282-এর ফাইল — এর ফোল্ডার অক্ষত থাকার প্রমাণ
    final s282Photo =
        '${_v2(storeDir.path, _oldClass, '1', '282', 'PHOTO')}/282.jpg';
    _write(s282Photo, 60);
    await DatabaseHelper.instance.updateImage('282', s282Photo);

    final before = await DatabaseHelper.instance.getStudentByDakhila('281');
    final updated = before!.copyWith(
      className: _newClass,
      forikNo: '2',
      stuName: 'রাসেল মাহমূদ',
    );

    final result = await provider.editStudentIdentity(updated);

    // সফল মুভ
    expect(result.ok, isTrue);
    expect(result.moved, 2);
    expect(result.failed, 0);

    // পুরনো ফাইল গেছে, নতুন জায়গায় আছে
    expect(File(oldPhotoPath).existsSync(), isFalse);
    expect(File(oldBirthPath).existsSync(), isFalse);
    final newPhotoPath =
        '${_v2(storeDir.path, _newClass, '2', '281', 'PHOTO')}/281.jpg';
    final newBirthPath =
        '${_v2(storeDir.path, _newClass, '2', '281', 'BIRTH')}/281.jpg';
    expect(File(newPhotoPath).existsSync(), isTrue);
    expect(File(newBirthPath).existsSync(), isTrue);
    expect(File(newPhotoPath).lengthSync(), 120);

    // DB: ছাত্র হালনাগাদ + image_path নতুন পাথে
    final after = await DatabaseHelper.instance.getStudentByDakhila('281');
    expect(after!.className, _newClass);
    expect(after.forikNo, '2');
    expect(after.stuName, 'রাসেল মাহমূদ');
    expect(after.imagePath, newPhotoPath);
    expect(after.isCaptured, 1);

    // documents টেবিলে নতুন পাথ
    final docs = await DatabaseHelper.instance.getStudentDocuments('281');
    final photo = docs.firstWhere((d) => d.type == DocType.PHOTO);
    final birth = docs.firstWhere((d) => d.type == DocType.BIRTH);
    expect(photo.filePath, newPhotoPath);
    expect(birth.filePath, newBirthPath);

    // পুরনো ছাত্র-ফোল্ডার মুছে গেছে (282-এর ফোল্ডার অক্ষত)
    expect(
        Directory(_v2(storeDir.path, _oldClass, '1', '281')).existsSync(),
        isFalse);
    expect(File(s282Photo).existsSync(), isTrue);
    expect(
        Directory(_v2(storeDir.path, _oldClass, '1', '282')).existsSync(),
        isTrue);

    // ক্লাস dropdown তালিকায় নতুন ক্লাস ঢুকেছে
    expect(provider.classes, contains(_newClass));
  });

  test('identity change without documents still updates class', () async {
    final dbDir = await Directory.systemTemp.createTemp('ident_db2');
    final storeDir = await Directory.systemTemp.createTemp('ident_store2');
    addTearDown(() async {
      await DatabaseHelper.instance.resetForTest();
      StorageService.testBaseDir = null;
      if (await dbDir.exists()) await dbDir.delete(recursive: true);
      if (await storeDir.exists()) await storeDir.delete(recursive: true);
    });
    final provider = await _setup('ident2', dbDir, storeDir);

    await DatabaseHelper.instance.replaceAllStudents([
      {
        'dakhila': '300',
        'stu_name': 'করিম',
        'class_name': _oldClass,
        'forik_no': '',
        'dakhila_year': '2026',
      },
    ]);

    final before = await DatabaseHelper.instance.getStudentByDakhila('300');
    final updated = before!.copyWith(className: _newClass, classLevel: '7');

    final result = await provider.editStudentIdentity(updated);

    expect(result.ok, isTrue);
    expect(result.moved, 0);
    expect(result.failed, 0);
    final after = await DatabaseHelper.instance.getStudentByDakhila('300');
    expect(after!.className, _newClass);
    expect(after.classLevel, '7');
    expect(after.forikNo, '');
  });

  test('same class+forik (level only) skips file move', () async {
    final dbDir = await Directory.systemTemp.createTemp('ident_db3');
    final storeDir = await Directory.systemTemp.createTemp('ident_store3');
    addTearDown(() async {
      await DatabaseHelper.instance.resetForTest();
      StorageService.testBaseDir = null;
      if (await dbDir.exists()) await dbDir.delete(recursive: true);
      if (await storeDir.exists()) await storeDir.delete(recursive: true);
    });
    final provider = await _setup('ident3', dbDir, storeDir);

    await DatabaseHelper.instance.replaceAllStudents([
      {
        'dakhila': '400',
        'stu_name': 'সালিম',
        'class_name': _oldClass,
        'forik_no': '3',
        'dakhila_year': '2026',
      },
    ]);
    final oldPhotoPath =
        '${_v2(storeDir.path, _oldClass, '3', '400', 'PHOTO')}/400.jpg';
    _write(oldPhotoPath, 50);
    await DatabaseHelper.instance.updateImage('400', oldPhotoPath);

    final before = await DatabaseHelper.instance.getStudentByDakhila('400');
    final updated = before!.copyWith(classLevel: '9', stuName: 'সালিম মাহমুদ');

    final result = await provider.editStudentIdentity(updated);

    expect(result.ok, isTrue);
    expect(result.moved, 0);
    expect(result.failed, 0);
    expect(File(oldPhotoPath).existsSync(), isTrue); // ফাইল জায়গায়ই
    final after = await DatabaseHelper.instance.getStudentByDakhila('400');
    expect(after!.classLevel, '9');
    expect(after.stuName, 'সালিম মাহমুদ');
    expect(after.imagePath, oldPhotoPath);
  });
}
