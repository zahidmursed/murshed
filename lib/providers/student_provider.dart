import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../db/database_helper.dart';
import '../models/document.dart';
import '../models/forik_stat.dart';
import '../models/student.dart';
import '../services/storage_service.dart';
import '../utils/excel_parser.dart';
import '../utils/gallery_saver.dart';

class StudentProvider extends ChangeNotifier {
  StudentProvider({SharedPreferences? prefs}) : _prefs = prefs {
    if (_prefs == null) return;
    isPassportMode = _prefs!.getBool('passportMode') ?? isPassportMode;
    isSerialMode = _prefs!.getBool('serialMode') ?? isSerialMode;
    isGridMode = _prefs!.getBool('gridMode') ?? isGridMode;
    final saved = _prefs!.getString('themeMode');
    if (saved != null) {
      themeMode = ThemeMode.values
          .firstWhere((m) => m.name == saved, orElse: () => ThemeMode.system);
    }
  }

  final SharedPreferences? _prefs;

  List<Student> _students = [];
  List<Student> _filtered = [];
  bool isLoading = true;
  String selectedForik = '';
  bool isPassportMode = true; // true = passport size 600x800
  bool isSerialMode = true;
  bool isGridMode = true;
  ThemeMode themeMode = ThemeMode.system;

  String selectedClass = '';
  List<String> classes = [];
  List<String> foriks = [];

  String _query = '';
  Timer? _debounce;
  int _searchRequest = 0;
  final Map<String, bool> _undoFlags = {};

  List<ForikStat> _forikStats = [];

  /// Phase 6: dakhila → (DocType → StudentDocument) — অনুপস্থিত = বাকি
  Map<String, Map<DocType, StudentDocument>> _docs = {};

  List<Student> get students => _filtered;
  List<ForikStat> get forikStats => _forikStats;
  int get total => _filtered.length;
  int get captured => _filtered.where((s) => s.isCaptured == 1).length;
  int get remaining => total - captured;

  /// Phase 6: ডকুমেন্ট হেল্পার
  StudentDocument? docOf(String dakhila, DocType type) => _docs[dakhila]?[type];

  int docCountOf(String dakhila) => _docs[dakhila]?.length ?? 0;

  StudentWithDocs withDocs(Student s) => StudentWithDocs(
        student: s,
        docs: {for (final t in DocType.values) t: _docs[s.dakhila]?[t]},
      );

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
    _docs = await DatabaseHelper.instance.getAllDocumentsMap();
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
    _prefs?.setBool('passportMode', v);
    notifyListeners();
  }

  void toggleSerial(bool v) {
    isSerialMode = v;
    _prefs?.setBool('serialMode', v);
    notifyListeners();
  }

  void setGridMode(bool v) {
    isGridMode = v;
    _prefs?.setBool('gridMode', v);
    notifyListeners();
  }

  void setThemeMode(ThemeMode mode) {
    themeMode = mode;
    _prefs?.setString('themeMode', mode.name);
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
    // 3-Doc: PHOTO doc মেমোরিতে আপডেট
    _docs.putIfAbsent(dakhila, () => {})[DocType.PHOTO] = StudentDocument(
      dakhila: dakhila,
      type: DocType.PHOTO,
      filePath: path,
      ext: path.contains('.') ? path.split('.').last.toLowerCase() : 'jpg',
      status: 1,
    );
    for (final list in [_students, _filtered]) {
      final i = list.indexWhere((s) => s.dakhila == dakhila);
      if (i != -1) list[i].totalDocs = _docs[dakhila]?.length ?? 0;
    }
    _forikStats = await DatabaseHelper.instance.getForikStats();
    notifyListeners();
  }

  /// ছবি মোছা (রেকর্ড রিসেট + ফাইল ট্র্যাশে সরানো — Undo সুবিধার জন্য)।
  /// রিটার্ন: ট্র্যাশ ফাইলের পাথ (null = ফাইল ছিল না)।
  Future<String?> clearCaptured(String dakhila) async {
    final sources = [..._students, ..._filtered];
    String? trashPath;
    for (final s in sources) {
      if (s.dakhila == dakhila && s.imagePath != null) {
        final src = File(s.imagePath!);
        if (await src.exists()) {
          try {
            final appDir = await getExternalStorageDirectory() ??
                await getApplicationDocumentsDirectory();
            final trashDir = Directory('${appDir.path}/Trash');
            if (!await trashDir.exists()) {
              await trashDir.create(recursive: true);
            }
            final stamp = DateTime.now().millisecondsSinceEpoch;
            trashPath = '${trashDir.path}/${dakhila}_$stamp.jpg';
            await src.rename(trashPath);
          } catch (e) {
            debugPrint('Trash move failed: $e');
          }
        }
        break;
      }
    }
    // গ্যালারির কপিও মুছে দিই (best-effort)
    await GallerySaver.deleteFromGallery(fileName: '$dakhila.jpg');

    await DatabaseHelper.instance.clearImage(dakhila);
    _docs[dakhila]?.remove(DocType.PHOTO);
    for (final list in [_students, _filtered]) {
      final idx = list.indexWhere((s) => s.dakhila == dakhila);
      if (idx != -1) {
        list[idx].imagePath = null;
        list[idx].isCaptured = 0;
        list[idx].totalDocs = _docs[dakhila]?.length ?? 0;
      }
    }
    _forikStats = await DatabaseHelper.instance.getForikStats();
    notifyListeners();
    if (trashPath != null) _scheduleTrashCleanup(trashPath);
    return trashPath;
  }

  /// ৬ সেকেন্ড পর ট্র্যাশ ফাইল মুছে ফেলে (Undo না করলে)।
  void _scheduleTrashCleanup(String trashPath) {
    _undoFlags[trashPath] = false;
    Future.delayed(const Duration(seconds: 6), () async {
      final undone = _undoFlags[trashPath] ?? false;
      _undoFlags.remove(trashPath);
      if (undone) return;
      try {
        final f = File(trashPath);
        if (await f.exists()) await f.delete();
      } catch (e) {
        debugPrint('Trash cleanup failed: $e');
      }
    });
  }

  /// Undo: ট্র্যাশ থেকে ছবি ফেরত + রেকর্ড পুনঃস্থাপন।
  Future<void> restoreFromTrash(String dakhila, String trashPath) async {
    _undoFlags[trashPath] = true;
    // ডিলিটের পর ইতিমধ্যে নতুন ছবি তোলা হলে restore বাদ — ট্র্যাশ মুছে যাবে
    final all = await DatabaseHelper.instance.getAllStudents();
    Student? current;
    for (final s in all) {
      if (s.dakhila == dakhila) {
        current = s;
        break;
      }
    }
    if (current != null && current.isCaptured == 1) {
      try {
        final f = File(trashPath);
        if (await f.exists()) await f.delete();
      } catch (_) {}
      return;
    }
    final appDir = await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    final dest = '${appDir.path}/DakhilaCamera/$dakhila.jpg';
    try {
      await File(trashPath).rename(dest);
    } catch (e) {
      debugPrint('Restore rename failed: $e');
      return;
    }
    await DatabaseHelper.instance.updateImage(dakhila, dest);
    _docs.putIfAbsent(dakhila, () => {})[DocType.PHOTO] = StudentDocument(
      dakhila: dakhila,
      type: DocType.PHOTO,
      filePath: dest,
      ext: 'jpg',
      status: 1,
    );
    for (final list in [_students, _filtered]) {
      final idx = list.indexWhere((s) => s.dakhila == dakhila);
      if (idx != -1) {
        list[idx].imagePath = dest;
        list[idx].isCaptured = 1;
        list[idx].totalDocs = _docs[dakhila]?.length ?? 0;
      }
    }
    _forikStats = await DatabaseHelper.instance.getForikStats();
    notifyListeners();
  }

  /// Fresh install/ফাইল হারানোর পর গ্যালারির কপি থেকে তোলা ছবি ফিরিয়ে আনে।
  /// দাখিলা নম্বর মিলিয়ে Pictures/DakhilaCamera → অ্যাপ ডিরেক্টরি কপি করে।
  /// রিটার্ন: রিকভার হওয়া ছবির সংখ্যা।
  Future<int> recoverFromGallery({
    void Function(int done, int total)? onProgress,
  }) async {
    final names = (await GallerySaver.listGalleryPhotos()).toSet();
    final all = await DatabaseHelper.instance.getAllStudents();
    final targets = all.where((s) {
      final name = '${s.dakhila}.jpg';
      if (!names.contains(name)) return false;
      // এমনিতে তোলা এবং ফাইল জায়গামতো আছে → দরকার নেই
      if (s.isCaptured == 1 &&
          s.imagePath != null &&
          File(s.imagePath!).existsSync()) {
        return false;
      }
      return true;
    }).toList();

    var done = 0;
    var restored = 0;
    for (final s in targets) {
      final name = '${s.dakhila}.jpg';
      final appDir = await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
      final dest = '${appDir.path}/DakhilaCamera/$name';
      final ok = await GallerySaver.copyGalleryPhoto(
        fileName: name,
        destPath: dest,
      );
      if (ok) {
        await DatabaseHelper.instance.updateImage(s.dakhila, dest);
        _docs.putIfAbsent(s.dakhila, () => {})[DocType.PHOTO] = StudentDocument(
          dakhila: s.dakhila,
          type: DocType.PHOTO,
          filePath: dest,
          ext: 'jpg',
          status: 1,
        );
        for (final list in [_students, _filtered]) {
          final idx = list.indexWhere((x) => x.dakhila == s.dakhila);
          if (idx != -1) {
            list[idx].imagePath = dest;
            list[idx].isCaptured = 1;
          }
        }
        restored++;
      }
      done++;
      onProgress?.call(done, targets.length);
    }
    if (restored > 0) {
      _forikStats = await DatabaseHelper.instance.getForikStats();
      notifyListeners();
    }
    return restored;
  }

  /// Phase 6: পুরনো flat ছবিগুলো v2 ফোল্ডার-লেআউটে সাজানো
  /// (copy → DB update → পুরনো ফাইল delete; ব্যর্থ হলে পুরনোটা অক্ষত)।
  Future<int> migrateStorageToV2({
    void Function(int done, int total)? onProgress,
  }) async {
    final all = await DatabaseHelper.instance.getAllStudents();
    final targets = all
        .where((s) =>
            s.isCaptured == 1 &&
            s.imagePath != null &&
            !s.imagePath!.contains('/v2/') &&
            File(s.imagePath!).existsSync())
        .toList();
    var done = 0;
    var moved = 0;
    for (final s in targets) {
      final newPath = await StorageService.copyToStudentFolder(
        className: s.className,
        forik: s.forikNo,
        dakhila: s.dakhila,
        type: DocType.PHOTO,
        oldPath: s.imagePath!,
      );
      if (newPath != null) {
        await DatabaseHelper.instance.updateImage(s.dakhila, newPath);
        for (final list in [_students, _filtered]) {
          final i = list.indexWhere((x) => x.dakhila == s.dakhila);
          if (i != -1) list[i].imagePath = newPath;
        }
        _docs[s.dakhila]?[DocType.PHOTO] = StudentDocument(
          dakhila: s.dakhila,
          type: DocType.PHOTO,
          filePath: newPath,
          ext: 'jpg',
          status: 1,
        );
        // DB আপডেট সফল — এখন পুরনো flat ফাইল মুছে ফেলা নিরাপদ
        try {
          final old = File(s.imagePath!);
          if (await old.exists()) await old.delete();
        } catch (_) {}
        moved++;
      }
      done++;
      onProgress?.call(done, targets.length);
    }
    return moved;
  }

  /// Phase 7: ডকুমেন্ট (PHOTO/BIRTH/FORM) ছাত্রের ফোল্ডারে কপি করে সেভ করে।
  Future<void> assignDocument({
    required String dakhila,
    required DocType type,
    required String srcPath,
  }) async {
    // ছাত্র খুঁজি (ফিল্টারে না থাকলে DB থেকে)
    Student? target;
    for (final x in _students) {
      if (x.dakhila == dakhila) {
        target = x;
        break;
      }
    }
    target ??= () {
      for (final x in _filtered) {
        if (x.dakhila == dakhila) return x;
      }
      return null;
    }();
    if (target == null) {
      final all = await DatabaseHelper.instance.getAllStudents();
      for (final x in all) {
        if (x.dakhila == dakhila) {
          target = x;
          break;
        }
      }
    }
    if (target == null) {
      throw StateError('$dakhila দাখিলার ছাত্র পাওয়া যায়নি');
    }

    final ext = srcPath.contains('.')
        ? srcPath.split('.').last.toLowerCase()
        : (type == DocType.PHOTO ? 'jpg' : 'pdf');
    final newPath = await StorageService.copyToStudentFolder(
      className: target.className,
      forik: target.forikNo,
      dakhila: dakhila,
      type: type,
      oldPath: srcPath,
    );
    if (newPath == null) throw StateError('ফাইল কপি ব্যর্থ');

    final mime = ext == 'pdf'
        ? 'application/pdf'
        : (ext == 'png' ? 'image/png' : 'image/jpeg');
    final doc = StudentDocument(
      dakhila: dakhila,
      type: type,
      filePath: newPath,
      ext: ext,
      mimeType: mime,
      status: 1,
      updatedAt: DateTime.now().toIso8601String(),
    );
    if (type == DocType.PHOTO) {
      await DatabaseHelper.instance.updateImage(dakhila, newPath);
    } else {
      await DatabaseHelper.instance.upsertDocument(doc);
    }
    _docs.putIfAbsent(dakhila, () => {})[type] = doc;
    for (final list in [_students, _filtered]) {
      final i = list.indexWhere((x) => x.dakhila == dakhila);
      if (i != -1) {
        if (type == DocType.PHOTO) {
          list[i].imagePath = newPath;
          list[i].isCaptured = 1;
        }
        list[i].totalDocs = _docs[dakhila]?.length ?? 0;
      }
    }
    notifyListeners();
  }

  /// ডকুমেন্ট মুছে ফেলা (ফাইল + DB)।
  Future<void> removeDocument({
    required String dakhila,
    required DocType type,
  }) async {
    final path = _docs[dakhila]?[type]?.filePath;
    if (type == DocType.PHOTO) {
      await DatabaseHelper.instance.clearImage(dakhila);
    } else {
      await DatabaseHelper.instance.deleteDocument(dakhila, type);
    }
    if (path != null) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (e) {
        debugPrint('Doc file delete failed: $e');
      }
    }
    _docs[dakhila]?.remove(type);
    for (final list in [_students, _filtered]) {
      final i = list.indexWhere((x) => x.dakhila == dakhila);
      if (i != -1) {
        if (type == DocType.PHOTO) {
          list[i].imagePath = null;
          list[i].isCaptured = 0;
        }
        list[i].totalDocs = _docs[dakhila]?.length ?? 0;
      }
    }
    _forikStats = await DatabaseHelper.instance.getForikStats();
    notifyListeners();
  }

  /// Phase 7: `281_BIRTH.pdf` নামের একাধিক ফাইল একসাথে ইমপোর্ট।
  Future<({int assigned, int skipped})> bulkImportDocuments(
      List<String> paths) async {
    var assigned = 0;
    var skipped = 0;
    for (final path in paths) {
      final parsed = parseBulkDocName(p.basename(path));
      if (parsed == null) {
        skipped++;
        continue;
      }
      final (dakhila, type) = parsed;
      try {
        await assignDocument(dakhila: dakhila, type: type, srcPath: path);
        assigned++;
      } catch (_) {
        skipped++;
      }
    }
    return (assigned: assigned, skipped: skipped);
  }

  /// Settings: সব তোলা ছবি গ্যালারিতে (Pictures/DakhilaCamera) ব্যাকআপ —
  /// একই নাম হলে replace হয়, তাই বারবার চালানো নিরাপদ।
  /// রিটার্ন: সফলভাবে ব্যাকআপ হওয়া ছবির সংখ্যা।
  Future<int> backupAllToGallery({
    void Function(int done, int total)? onProgress,
  }) async {
    final all = await DatabaseHelper.instance.getAllStudents();
    final captured =
        all.where((s) => s.isCaptured == 1 && s.imagePath != null).toList();
    var done = 0;
    var ok = 0;
    for (final s in captured) {
      final f = File(s.imagePath!);
      if (await f.exists()) {
        final saved = await GallerySaver.saveToGallery(
          filePath: s.imagePath!,
          fileName: '${s.dakhila}.jpg',
        );
        if (saved) ok++;
      }
      done++;
      onProgress?.call(done, captured.length);
    }
    return ok;
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

  /// ডিভাইস থেকে বাছাই করা Excel (.xlsx) ফাইল ইমপোর্ট।
  Future<int> importFromExcelFile(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    final maps = await ExcelParser.parseFromBytesInIsolate(bytes);
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
