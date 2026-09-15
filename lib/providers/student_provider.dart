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
import '../utils/image_processor.dart';

class StudentProvider extends ChangeNotifier {
  StudentProvider({SharedPreferences? prefs}) : _prefs = prefs {
    if (_prefs == null) return;
    isPassportMode = _prefs!.getBool('passportMode') ?? isPassportMode;
    isSerialMode = _prefs!.getBool('serialMode') ?? isSerialMode;
    isGridMode = _prefs!.getBool('gridMode') ?? isGridMode;
    isAutoEnhancementEnabled =
        _prefs!.getBool('autoEnhancementEnabled') ?? isAutoEnhancementEnabled;
    final preset = _prefs!.getString('passportPreset');
    if (preset != null) {
      passportPreset = PassportPreset.values.firstWhere(
        (p) => p.name == preset,
        orElse: () => PassportPreset.fresh,
      );
    }
    final saved = _prefs!.getString('themeMode');
    if (saved != null) {
      themeMode = ThemeMode.values
          .firstWhere((m) => m.name == saved, orElse: () => ThemeMode.system);
    }
    institutionName = _prefs!.getString('institutionName') ?? '';
    institutionLogoPath = _prefs!.getString('institutionLogoPath');
  }

  final SharedPreferences? _prefs;

  List<Student> _students = [];
  List<Student> _filtered = [];
  bool isLoading = true;
  String selectedForik = '';
  bool isPassportMode = true; // true = passport size 431x531 + auto enhance
  bool isSerialMode = true;
  bool isGridMode = true;
  bool isAutoEnhancementEnabled = true;
  PassportPreset passportPreset = PassportPreset.fresh;
  ThemeMode themeMode = ThemeMode.system;

  void setPassportPreset(PassportPreset preset) {
    passportPreset = preset;
    _prefs?.setString('passportPreset', preset.name);
    notifyListeners();
  }

  void setAutoEnhancementEnabled(bool enabled) {
    isAutoEnhancementEnabled = enabled;
    _prefs?.setBool('autoEnhancementEnabled', enabled);
    notifyListeners();
  }

  String selectedClass = '';
  List<String> classes = [];
  List<String> foriks = [];

  String _query = '';
  Timer? _debounce;
  int _searchRequest = 0;
  final Map<String, bool> _undoFlags = {};
  bool _trashSwept = false;

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

  Future<void>? _loadQueue;

  /// reentrancy guard: চলমান load থাকলে সেটার পরে নতুনটা চলে — দ্রুত
  /// ফিল্টার ট্যাপে পুরনো/নতুন ফলাফল মিশে যাওয়া (interleaving) আটকায়;
  /// শেষে সর্বশেষ ফিল্টারের ফলাফলই পর্দায় থাকে।
  Future<void> load() {
    final prev = _loadQueue;
    final future = () async {
      try {
        await prev;
      } catch (_) {}
      await _doLoad();
    }();
    _loadQueue = future;
    return future;
  }

  Future<void> _doLoad() async {
    isLoading = true;
    notifyListeners();
    // স্টোরেজ ফিক্স: অ্যাপ রানে একবার পুরনো ট্র্যাশ ফাইল পরিষ্কার (নিচে দেখুন)
    unawaited(_sweepTrashOnce());
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

  // ---- প্রতিষ্ঠান কাস্টমাইজ (নাম/লোগো) — অ্যাপ হেডার ও রিপোর্ট ফরমে দেখা যায় ----
  String institutionName = '';
  String? institutionLogoPath;

  void setInstitutionName(String name) {
    institutionName = name.trim();
    _prefs?.setString('institutionName', institutionName);
    notifyListeners();
  }

  Future<void> setInstitutionLogo(String? path) async {
    institutionLogoPath = path;
    if (path == null) {
      await _prefs?.remove('institutionLogoPath');
    } else {
      await _prefs?.setString('institutionLogoPath', path);
    }
    notifyListeners();
  }

  /// বাগ ফিক্স: ফরিক স্ট্যাট সবসময় বর্তমান ক্লাস ফিল্টার মেনে রিফ্রেশ হয়।
  /// আগে কয়েকটি মেথড ফিল্টার ছাড়া getForikStats() কল করত — ফলে ক্লাস বাছাই
  /// করা অবস্থায় ক্যাপচার/ডিলিটের পরেই chip-গুলোতে সব ক্লাসের ফরিক ঢুকে যেত।
  Future<void> _refreshForikStats() async {
    final String? classFilter = selectedClass.isEmpty ? null : selectedClass;
    _forikStats = await DatabaseHelper.instance.getForikStats(
      classFilter: classFilter,
    );
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
    await _refreshForikStats();
    notifyListeners();
  }

  /// ক্যামেরা/ডিস্ক থেকে সরাসরি ডকুমেন্ট সেভ (ফাইল আগেই সঠিক পাথে থাকলে)।
  Future<void> markDocumentSaved(
      String dakhila, DocType type, String path) async {
    final ext =
        path.contains('.') ? path.split('.').last.toLowerCase() : 'jpg';
    final doc = StudentDocument(
      dakhila: dakhila,
      type: type,
      filePath: path,
      ext: ext,
      mimeType: StudentDocument.mimeTypeForExt(ext),
      status: 1,
      updatedAt: DateTime.now().toIso8601String(),
    );
    await DatabaseHelper.instance.upsertDocument(doc);
    _docs.putIfAbsent(dakhila, () => {})[type] = doc;
    for (final list in [_students, _filtered]) {
      final i = list.indexWhere((x) => x.dakhila == dakhila);
      if (i != -1) list[i].totalDocs = _docs[dakhila]?.length ?? 0;
    }
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
    await _refreshForikStats();
    notifyListeners();
    if (trashPath != null) _scheduleTrashCleanup(trashPath);
    return trashPath;
  }

  /// স্টোরেজ ফিক্স: Undo-র ৬ সেকেন্ড উইন্ডোর মধ্যে অ্যাপ বন্ধ হলে
  /// Future.delayed আর চলে না — ট্র্যাশ ফাইল ফাঁকি থেকে যেত। প্রতি রানে
  /// একবার ট্র্যাশ স্ক্যান করে ১ মিনিটের পুরনো ফাইল মুছে দেয় (সদ্য তৈরি
  /// ফাইল = সম্ভবত চলমান Undo উইন্ডো — সেটা নিজের টাইমারে মুছে যাবে)।
  Future<void> _sweepTrashOnce() async {
    if (_trashSwept) return;
    _trashSwept = true;
    try {
      final appDir = await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
      final trashDir = Directory('${appDir.path}/Trash');
      if (!await trashDir.exists()) return;
      final cutoff = DateTime.now().subtract(const Duration(minutes: 1));
      await for (final entity in trashDir.list()) {
        if (entity is! File) continue;
        try {
          final stat = await entity.stat();
          if (stat.modified.isBefore(cutoff)) await entity.delete();
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('Trash sweep failed: $e');
    }
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
    // বাগ ফিক্স: v2 লেআউটেই ফেরত বসানো (আগে পুরনো flat DakhilaCamera/ ফোল্ডারে
    // যেত — ফলে ফোল্ডার-গঠন অসঙ্গত হতো ও আবার তুললে orphan ফাইল থেকে যেত)।
    if (current == null) {
      // DB-তে ছাত্র নেই — ফেরানো অর্থহীন; ট্র্যাশ ফাইল পরিষ্কার করে দিই।
      try {
        final stale = File(trashPath);
        if (await stale.exists()) await stale.delete();
      } catch (_) {}
      return;
    }
    final dest = await StorageService.documentPath(
      current.className,
      current.forikNo,
      dakhila,
      DocType.PHOTO,
      'jpg',
    );
    try {
      await File(trashPath).rename(dest);
    } catch (e) {
      // একই ভলিউমে rename ব্যর্থ হলে copy+delete fallback
      try {
        await File(trashPath).copy(dest);
        await File(trashPath).delete();
      } catch (e2) {
        debugPrint('Restore failed: $e2');
        return;
      }
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
    await _refreshForikStats();
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
      // বাগ ফিক্স: v2 লেআউটে রিকভারি — documentPath নিজেই ফোল্ডার তৈরি করে দেয়।
      final dest = await StorageService.documentPath(
        s.className,
        s.forikNo,
        s.dakhila,
        DocType.PHOTO,
        'jpg',
      );
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
      await _refreshForikStats();
      notifyListeners();
    }
    return restored;
  }

  /// পুরনো flat/v2 ফাইলকে student/PHOTO|BIRTH|FORM/দাখিলা.ext লেআউটে সাজায়।
  /// Copy ও DB update সফল হওয়ার আগে কোনো source file মুছে না, তাই মাঝপথে
  /// ব্যর্থ হলেও পুরনো ফাইল অক্ষত থাকে।
  Future<int> migrateStorageToV2({
    void Function(int done, int total)? onProgress,
  }) async {
    final all = await DatabaseHelper.instance.getAllStudents();
    final docsByDakhila = await DatabaseHelper.instance.getAllDocumentsMap();
    final targets = <(Student, StudentDocument)>[];
    for (final student in all) {
      final docs = docsByDakhila[student.dakhila]?.values.toList() ?? [];
      final hasPhotoDoc = docs.any((doc) => doc.type == DocType.PHOTO);
      for (final doc in docs) {
        if (File(doc.filePath).existsSync() && !_isStructuredPath(doc)) {
          targets.add((student, doc));
        }
      }
      // খুব পুরনো DB-তে PHOTO document row না থাকলেও image_path থাকলে সেটিও সাজাই।
      if (!hasPhotoDoc &&
          student.imagePath != null &&
          File(student.imagePath!).existsSync()) {
        final ext = p.extension(student.imagePath!).replaceFirst('.', '');
        targets.add((
          student,
          StudentDocument(
            dakhila: student.dakhila,
            type: DocType.PHOTO,
            filePath: student.imagePath!,
            ext: ext.isEmpty ? 'jpg' : ext,
          ),
        ));
      }
    }
    var done = 0;
    var moved = 0;
    for (final (student, doc) in targets) {
      final oldPath = doc.filePath; // mutation-এর আগে source path ধরে রাখি
      final newPath = await StorageService.copyToStudentFolder(
        className: student.className,
        forik: student.forikNo,
        dakhila: student.dakhila,
        type: doc.type,
        oldPath: oldPath,
      );
      if (newPath != null) {
        try {
          if (doc.type == DocType.PHOTO) {
            await DatabaseHelper.instance.updateImage(student.dakhila, newPath);
          } else {
            await DatabaseHelper.instance.upsertDocument(StudentDocument(
              dakhila: student.dakhila,
              type: doc.type,
              filePath: newPath,
              ext: doc.ext,
              mimeType: doc.mimeType,
              status: doc.status,
            ));
          }
          for (final list in [_students, _filtered]) {
            final i = list.indexWhere((x) => x.dakhila == student.dakhila);
            if (i != -1 && doc.type == DocType.PHOTO) {
              list[i].imagePath = newPath;
            }
          }
          _docs.putIfAbsent(student.dakhila, () => {})[doc.type] =
              StudentDocument(
            dakhila: student.dakhila,
            type: doc.type,
            filePath: newPath,
            ext: doc.ext,
            mimeType: doc.mimeType,
            status: doc.status,
          );
          // নতুন path-এ কপি ও DB record দুই-ই সফল; এবার শুধু source মুছি।
          final oldFile = File(oldPath);
          if (oldPath != newPath && await oldFile.exists()) {
            await oldFile.delete();
          }
          moved++;
        } catch (_) {
          // DB update/delete ব্যর্থ হলেও source রাখা হয়; পরেরবার আবার চেষ্টা করা যাবে।
        }
      }
      done++;
      onProgress?.call(done, targets.length);
    }
    if (moved > 0) notifyListeners();
    return moved;
  }

  bool _isStructuredPath(StudentDocument doc) {
    final parts = doc.filePath.replaceAll('\\', '/').split('/');
    return parts.length >= 2 && parts[parts.length - 2] == doc.type.name;
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
    if (type == DocType.BIRTH && ext == 'pdf') {
      throw StateError('জন্মসনদ অবশ্যই JPG/PNG ফরম্যাটে হবে (PDF নয়)');
    }
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
    final document = _docs[dakhila]?[type];
    final path = document?.filePath;
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
    // Public gallery backup-ও একই document-এর সঙ্গে সরাই।
    if (document != null && document.ext.toLowerCase() != 'pdf') {
      final fileName = type == DocType.PHOTO
          ? '$dakhila.${document.ext}'
          : '${dakhila}_${type.name}.${document.ext}';
      await GallerySaver.deleteFromGallery(fileName: fileName);
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
    await _refreshForikStats();
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

  /// Settings: সব image document গ্যালারির public Pictures/DakhilaCamera-তে
  /// ব্যাকআপ করে। ফলে Android/data লুকানো থাকলেও PHOTO/BIRTH/FORM দেখা যায়।
  /// PDF অ্যাপের নিজের FORM folder-এ থাকে; MediaStore image album-এ PDF রাখা হয় না।
  Future<int> backupAllToGallery({
    void Function(int done, int total)? onProgress,
  }) async {
    final docs = await DatabaseHelper.instance.getAllDocumentsMap();
    final imageDocs = docs.values
        .expand((byType) => byType.values)
        .where((doc) => doc.ext.toLowerCase() != 'pdf')
        .toList();
    var done = 0;
    var ok = 0;
    for (final doc in imageDocs) {
      final f = File(doc.filePath);
      if (await f.exists()) {
        final fileName = doc.type == DocType.PHOTO
            ? '${doc.dakhila}.${doc.ext}'
            : '${doc.dakhila}_${doc.type.name}.${doc.ext}';
        final saved = await GallerySaver.saveToGallery(
          filePath: doc.filePath,
          fileName: fileName,
        );
        if (saved) ok++;
      }
      done++;
      onProgress?.call(done, imageDocs.length);
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
