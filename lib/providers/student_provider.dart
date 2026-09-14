import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../models/forik_stat.dart';
import '../models/student.dart';
import '../utils/gallery_saver.dart';

class StudentProvider extends ChangeNotifier {
  List<Student> _students = [];
  List<Student> _filtered = [];
  bool isLoading = true;
  String selectedForik = '';
  bool isPassportMode = true; // true = passport size 600x800
  bool isSerialMode = true;

  String selectedClass = '';
  List<String> classes = [];
  List<String> foriks = [];

  String _query = '';
  Timer? _debounce;
  int _searchRequest = 0;

  List<ForikStat> _forikStats = [];

  List<Student> get students => _filtered;
  List<ForikStat> get forikStats => _forikStats;
  int get total => _filtered.length;
  int get captured => _filtered.where((s) => s.isCaptured == 1).length;
  int get remaining => total - captured;

  Future<void> load() async {
    isLoading = true;
    notifyListeners();
    await DatabaseHelper.instance.importJsonIfEmpty();
    final String? classFilter = selectedClass.isEmpty ? null : selectedClass;
    classes = await DatabaseHelper.instance.getDistinctClasses();
    foriks = await DatabaseHelper.instance.getForiksForClass(
      className: classFilter,
    );
    _students = await DatabaseHelper.instance.getAllStudents(
      forikFilter: selectedForik.isEmpty ? null : selectedForik,
      classFilter: classFilter,
    );
    _forikStats = await DatabaseHelper.instance.getForikStats(
      classFilter: classFilter,
    );
    isLoading = false;
    if (_query.isEmpty) {
      _filtered = _students;
      notifyListeners();
    } else {
      // ফরিক পরিবর্তনের পরেও চলমান সার্চ প্রযোজ্য থাকবে
      await _runSearch(_query);
    }
  }

  void setForik(String f) {
    selectedForik = f;
    load();
  }

  void setClass(String c) {
    selectedClass = c;
    selectedForik = ''; // ক্লাস বদলালে ফরিক আবার বাছতে হবে
    load();
  }

  /// ক্লাস + ফরিক দুটোই রিসেট ("All" বাটন)।
  void resetFilters() {
    selectedClass = '';
    selectedForik = '';
    load();
  }

  /// সার্চের সময় নির্বাচিত ফরিক filter-ও প্রয়োগ হবে।
  /// প্রতিটি কিস্ট্রোকে DB না চাপিয়ে 300ms ডিবাউন্স করা হয়।
  void search(String q) {
    _query = q;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _runSearch(_query);
    });
  }

  Future<void> _runSearch(String q) async {
    final int requestId = ++_searchRequest;
    final String? forik = selectedForik.isEmpty ? null : selectedForik;
    final List<Student> results = q.isEmpty
        ? _students
        : await DatabaseHelper.instance.search(
            q,
            forikFilter: forik,
            classFilter: selectedClass.isEmpty ? null : selectedClass,
          );
    if (requestId != _searchRequest) return; // পুরনো (stale) ফলাফল বাদ
    _filtered = results;
    notifyListeners();
  }

  void togglePassport(bool v) {
    isPassportMode = v;
    notifyListeners();
  }

  void toggleSerial(bool v) {
    isSerialMode = v;
    notifyListeners();
  }

  Future<void> markCaptured(String dakhila, String path) async {
    final idx = _students.indexWhere((s) => s.dakhila == dakhila);
    if (idx != -1) {
      _students[idx].imagePath = path;
      _students[idx].isCaptured = 1;
    }
    final fIdx = _filtered.indexWhere((s) => s.dakhila == dakhila);
    if (fIdx != -1) {
      _filtered[fIdx].imagePath = path;
      _filtered[fIdx].isCaptured = 1;
    }
    _forikStats = await DatabaseHelper.instance.getForikStats();
    notifyListeners();
  }

  /// ছবির ফাইল ডিলিট + রেকর্ড রিসেট (viewer-এর delete অ্যাকশন)।
  Future<void> clearCaptured(String dakhila) async {
    final sources = [..._students, ..._filtered];
    for (final s in sources) {
      if (s.dakhila == dakhila && s.imagePath != null) {
        try {
          final f = File(s.imagePath!);
          if (await f.exists()) await f.delete();
        } catch (e) {
          debugPrint('Image delete failed: $e');
        }
        break;
      }
    }
    // গ্যালারির কপিও মুছে দিই (best-effort)
    await GallerySaver.deleteFromGallery(fileName: '$dakhila.jpg');

    await DatabaseHelper.instance.clearImage(dakhila);
    for (final list in [_students, _filtered]) {
      final idx = list.indexWhere((s) => s.dakhila == dakhila);
      if (idx != -1) {
        list[idx].imagePath = null;
        list[idx].isCaptured = 0;
      }
    }
    _forikStats = await DatabaseHelper.instance.getForikStats();
    notifyListeners();
  }

  /// ডিভাইস থেকে বাছাই করা JSON ফাইল ইমপোর্ট (পুরনো ডেটার বদলে)।
  Future<int> importFromJsonFile(String filePath) async {
    final raw = await File(filePath).readAsString();
    final List<Map<String, dynamic>> maps =
        await Isolate.run(() => Student.parseJsonToMaps(raw));
    if (maps.isEmpty) return 0;
    final imported = await DatabaseHelper.instance.replaceAllStudents(maps);
    await load();
    return imported;
  }

  /// সব রেকর্ড মুছে বান্ডেল ডেটা পুনরায় ইমপোর্ট (পরের load()-এ)।
  Future<void> resetData() async {
    selectedForik = '';
    _query = '';
    await DatabaseHelper.instance.deleteAllStudents();
    await load();
  }

  Student? getNext(String currentDakhila) {
    final int i = _filtered.indexWhere((s) => s.dakhila == currentDakhila);
    if (i != -1 && i + 1 < _filtered.length) {
      return _filtered[i + 1];
    }
    return null;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
