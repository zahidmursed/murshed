import 'package:flutter/foundation.dart';

import '../db/database_helper.dart';
import '../models/teacher.dart';
import '../services/teacher_directory.dart';

/// শিক্ষক-তালিকার অ্যাপ-লেভেল স্টেট — DB-র `teachers` টেবিল থেকে লোড,
/// যোগ/সম্পাদনা/মুছে ফেলা/সিড-পুনরুদ্ধার। রিপোর্ট ফরম ও ম্যানেজ স্ক্রিন দুটোই
/// এই provider দেখে — সম্পাদনার সাথে সাথে UI হালনাগাদ হয়।
class TeacherProvider extends ChangeNotifier {
  List<TeacherInfo> _teachers = const [];
  bool _loaded = false;
  bool _loading = false;

  List<TeacherInfo> get teachers => _teachers;
  bool get loaded => _loaded;

  /// ছাত্রের ক্লাস+ফরিক দিয়ে দায়িত্বপ্রাপ্ত শিক্ষক (exact → ক্লাস-লেভেল → null)।
  TeacherInfo? find(String className, String forikNo) =>
      TeacherDirectory.find(_teachers, className, forikNo);

  /// প্রথম ব্যবহারে একবার DB থেকে লোড (idempotent)।
  Future<void> ensureLoaded() async {
    if (_loaded || _loading) return;
    _loading = true;
    try {
      _teachers = await DatabaseHelper.instance.getTeachers();
      _loaded = true;
      notifyListeners();
    } catch (e) {
      debugPrint('TeacherProvider load failed: $e');
    } finally {
      _loading = false;
    }
  }

  /// শিক্ষক যোগ/সম্পাদনা — (class_name, forik) natural key দিয়ে replace।
  /// true = সফল।
  Future<bool> upsert(TeacherInfo t) async {
    final ok = await DatabaseHelper.instance.upsertTeacher(
      TeacherInfo(
        className: TeacherDirectory.normText(t.className),
        forik: TeacherDirectory.normText(t.forik),
        nameBn: TeacherDirectory.normText(t.nameBn),
        nameEn: TeacherDirectory.normText(t.nameEn),
        mobile: TeacherDirectory.normMobile(t.mobile),
      ),
    );
    if (ok) await _reload();
    return ok;
  }

  /// শিক্ষক মুছে ফেলা। true = সফল (রো মুছেছে)।
  Future<bool> delete(String className, String forik) async {
    final n = await DatabaseHelper.instance.deleteTeacher(
        TeacherDirectory.normText(className), TeacherDirectory.normText(forik));
    if (n > 0) await _reload();
    return n > 0;
  }

  /// সব শিক্ষক মুছে bundled xlsx থেকে পুনরায় সিড। রিটার্ন: নতুন মোট সংখ্যা।
  Future<int> restoreSeed() async {
    final count = await DatabaseHelper.instance.restoreTeacherSeed();
    await _reload();
    return count;
  }

  Future<void> _reload() async {
    _teachers = await DatabaseHelper.instance.getTeachers();
    _loaded = true;
    notifyListeners();
  }
}
