import 'package:flutter/foundation.dart';

import '../db/database_helper.dart';
import '../models/case_note.dart';

/// কেস নোটের অ্যাপ-লেভেল স্টেট — DB থেকে একবার সব নোট লোড করে রাখে;
/// যোগ/সম্পাদনা/মুছে ফেলার সাথে সাথে রিপোর্ট ফরম ও নোট স্ক্রিন হালনাগাদ হয়।
class CaseNotesProvider extends ChangeNotifier {
  List<CaseNote> _notes = const [];
  bool _loaded = false;
  bool _loading = false;

  List<CaseNote> get notes => _notes;
  bool get loaded => _loaded;

  /// এক ছাত্রের নোট সংখ্যা (রিপোর্ট ফরমের কার্ডে)।
  int countFor(String dakhila) =>
      _notes.where((n) => n.dakhila == dakhila).length;

  /// এক ছাত্রের সব নোট (নতুন থেকে পুরনো ক্রমে)।
  List<CaseNote> notesFor(String dakhila) {
    final list = _notes.where((n) => n.dakhila == dakhila).toList();
    list.sort((a, b) => (b.createdAt ?? '').compareTo(a.createdAt ?? ''));
    return list;
  }

  /// প্রথম ব্যবহারে একবার লোড (idempotent)।
  Future<void> ensureLoaded() async {
    if (_loaded || _loading) return;
    _loading = true;
    try {
      _notes = await DatabaseHelper.instance.getAllCaseNotes();
      _loaded = true;
      notifyListeners();
    } catch (e) {
      debugPrint('CaseNotesProvider load failed: $e');
    } finally {
      _loading = false;
    }
  }

  /// নোট যোগ/সম্পাদনা। true = সফল।
  Future<bool> upsert(CaseNote note) async {
    final ok = await DatabaseHelper.instance.upsertCaseNote(note);
    if (ok) await _reload();
    return ok;
  }

  /// নোট মুছে ফেলা। true = সফল।
  Future<bool> delete(int id) async {
    final n = await DatabaseHelper.instance.deleteCaseNote(id);
    if (n > 0) await _reload();
    return n > 0;
  }

  Future<void> _reload() async {
    _notes = await DatabaseHelper.instance.getAllCaseNotes();
    _loaded = true;
    notifyListeners();
  }
}
