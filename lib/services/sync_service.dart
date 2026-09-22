import 'dart:io';

import 'package:flutter/foundation.dart'
    show ChangeNotifier, debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

import '../db/database_helper.dart';
import '../models/document.dart';
import '../models/sync_models.dart';
import 'sync_api.dart';

/// সিঙ্ক-ইঞ্জিনের অবস্থা (UI-তে দেখানোর জন্য)।
enum SyncPhase { notConfigured, offline, idle, pulling, uploading }

/// S2: অফলাইন-ফার্স্ট সিঙ্ক ইঞ্জিন।
///
/// নীতি: **অ্যাপ কখনো নেটওয়ার্ক-বাধ্য নয়**। লগইন না থাকলে/সার্ভার না মিললে
/// সব কাজ আগের মতোই ফোনে হয়; সুযোগ পেলেই (ওয়াইফাই + অ্যাপ চালু) সার্ভারের
/// সাথে মিলিয়ে নেয়।
///
/// * **pull** — সার্ভারের ছাত্র-তালিকা/ডক-রেজিস্ট্রি নামায় (delta: `lastSyncAt`)
/// * **push** — `sync_state != 'synced'` ছবিগুলো সার্ভারে ওঠায় (sha256 dedup)
/// * **pushStudents** — admin চাইলে পুরো তালিকা সার্ভারে বসায়
class SyncService extends ChangeNotifier {
  SyncService({required SharedPreferences prefs, DatabaseHelper? db})
      : _prefs = prefs,
        _db = db ?? DatabaseHelper.instance {
    _settings = SyncSettings.load(prefs);
  }

  final SharedPreferences _prefs;
  final DatabaseHelper _db;

  late SyncSettings _settings;
  SyncSettings get settings => _settings;

  SyncPhase _phase = SyncPhase.notConfigured;
  SyncPhase get phase => _phase;

  bool _busy = false;
  bool get isBusy => _busy;

  String _status = '';
  String get status => _status;

  String _lastError = '';
  String get lastError => _lastError;

  SyncReport? _lastReport;
  SyncReport? get lastReport => _lastReport;

  final Map<String, int> _counts = {
    'pending': 0,
    'synced': 0,
    'failed': 0,
    'skipped': 0,
    'total': 0,
  };
  Map<String, int> get counts => Map.unmodifiable(_counts);

  int get pendingDocs => _counts['pending'] ?? 0;
  int get syncedDocs => _counts['synced'] ?? 0;

  Map<String, int> _cloud = {};
  Map<String, int> get cloudStats => Map.unmodifiable(_cloud);

  int _studentCount = 0;
  int get studentCount => _studentCount;

  List<Map<String, dynamic>> _logs = [];
  List<Map<String, dynamic>> get recentLogs => List.unmodifiable(_logs);

  DateTime? _lastAutoAttempt;

  SyncApi get _api =>
      SyncApi(baseUrl: _settings.serverUrl, token: _settings.token);

  bool get isConfigured => _settings.isLoggedIn;

  /// অ্যাপ চালুতে একবার — ডিভাইস-আইডি নিশ্চিত + হিসাব লোড।
  Future<void> init() async {
    _settings.deviceId = await SyncSettings.ensureDeviceId(_prefs);
    await refresh();
    _phase = isConfigured ? SyncPhase.idle : SyncPhase.notConfigured;
    notifyListeners();
  }

  /// DB থেকে ব্যাজ/হিসাব হালনাগাদ (কোনো নেটওয়ার্ক কল নয়)।
  Future<void> refresh() async {
    try {
      final counts = await _db.docSyncCounts();
      _counts
        ..['pending'] = counts['pending'] ?? 0
        ..['synced'] = counts['synced'] ?? 0
        ..['failed'] = counts['failed'] ?? 0
        ..['skipped'] = counts['skipped'] ?? 0
        ..['total'] = counts['total'] ?? 0;
      _cloud = await _db.cloudDocStats();
      _studentCount = (await _db.getStudentsForUpload()).length;
      _logs = await _db.recentSyncLogs(limit: 5);
    } catch (e) {
      debugPrint('SyncService.refresh: $e');
    }
    notifyListeners();
  }

  /// তালিকা/পছন্দ বদল।
  Future<void> setAutoSync(bool value) async {
    _settings.autoSync = value;
    await _settings.save(_prefs);
    notifyListeners();
  }

  Future<void> setWifiOnly(bool value) async {
    _settings.wifiOnly = value;
    await _settings.save(_prefs);
    notifyListeners();
  }

  /// সংযোগ পরীক্ষা (লগইন ছাড়াও চলে — ping.php)।
  Future<PingResult> testConnection(String rawUrl) async {
    final api = SyncApi(baseUrl: rawUrl);
    return api.ping();
  }

  /// লগইন — সফল হলে সেটিংস সংরক্ষণ করে হিসাব হালনাগাদ।
  /// [rawUrl] ইউজারের লেখা হোক (`192.168.0.5/dakhila`)।
  Future<LoginResult> login({
    required String rawUrl,
    required String email,
    required String password,
  }) async {
    final base = SyncApi.normalizeBase(rawUrl);
    if (base.isEmpty) {
      throw const SyncApiException(0, 'NO_SERVER', 'সার্ভারের ঠিকানা দিন');
    }
    final api = SyncApi(baseUrl: base);
    // আগে ping — লগইনের ভুল কেন ব্যর্থ হলো তা স্পষ্ট হয়
    await api.ping();
    final res = await api.login(email.trim(), password);
    _settings.serverUrl = base;
    _settings.email = email.trim();
    _settings.token = res.token;
    _settings.teacherName = res.name;
    _settings.role = res.role;
    _settings.lastSyncAt = null; // নতুন লগইন = পূর্ণ pull
    await _settings.save(_prefs);
    _lastError = '';
    _phase = SyncPhase.idle;
    await refresh();
    return res;
  }

  /// লগআউট — টোকেন বাদ। ছবি/ডেটা কিছুই মোছে না (অফলাইন অ্যাপ আগের মতো চলে)।
  Future<void> logout() async {
    await _settings.clearSession(_prefs);
    _phase = SyncPhase.notConfigured;
    _status = '';
    _lastError = '';
    notifyListeners();
  }

  /// আগের সব ছবি সার্ভারে যাবে কি না (সংযোগ-স্থাপনের সিদ্ধান্ত)।
  /// [uploadAll] true → সব আপলোড হবে; false → শুধু নতুন ছবি।
  Future<void> setUploadOldPhotos(bool uploadAll) async {
    final n = await _db.setAllDocsSyncState(uploadAll);
    _status = uploadAll
        ? '$n টি পুরনো ছবি আপলোড-তালিকায় যোগ হয়েছে'
        : '$n টি পুরনো ছবি বাদ — এখন থেকে শুধু নতুন ছবি যাবে';
    await refresh();
  }

  /// সার্ভারে পৌঁছানো যায় কি না (TCP-সংযোগ পরীক্ষা, ৪ সেকেন্ড)।
  Future<bool> serverReachable() async {
    if (_settings.serverUrl.isEmpty) return false;
    final uri = Uri.tryParse(_settings.serverUrl);
    final host = uri?.host ?? '';
    if (host.isEmpty) return false;
    final port = uri?.hasPort == true
        ? uri!.port
        : (uri?.scheme == 'https' ? 443 : 80);
    try {
      final socket = await Socket.connect(host, port,
          timeout: const Duration(seconds: 4));
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// ওয়াইফাইতে আছি কি না — প্লাগইন ছাড়াই নেটওয়ার্ক-ইন্টারফেসের নাম থেকে
  /// (Android-এ `wlan0`)। নিশ্চিত না হলে false — কিন্তু ম্যানুয়াল সিঙ্ক
  /// তখনও চলে (ইউজার নিজেই চাপ দিয়েছেন)।
  Future<bool> onWifi() async {
    try {
      final ifaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4, includeLoopback: false);
      return ifaces.any((i) => i.name.toLowerCase().startsWith('wlan'));
    } catch (_) {
      return false;
    }
  }

  /// অ্যাপ চালু/তালিকায় ফেরার সময় নিজে নিজে সিঙ্ক (ব্যর্থ হলে চুপ)।
  Future<void> maybeAutoSync(
      {Duration minInterval = const Duration(minutes: 2)}) async {
    if (!isConfigured || !_settings.autoSync || _busy) return;
    final now = DateTime.now();
    if (_lastAutoAttempt != null &&
        now.difference(_lastAutoAttempt!) < minInterval) {
      return;
    }
    _lastAutoAttempt = now;
    if (!await serverReachable()) {
      _phase = SyncPhase.offline;
      notifyListeners();
      return;
    }
    try {
      await syncNow();
    } catch (_) {
      // অটো-সিঙ্ক চুপচাপ ব্যর্থ — ইউজার চাইলে নিজে চালাবেন
    }
  }
/// সম্পূর্ণ সিঙ্ক: সার্ভারের হালনাগাদ নামানো → অপেক্ষমাণ ছবি পাঠানো।
  /// [uploadStudents] true হলে (admin) পুরো তালিকা সার্ভারে বসানো হয়।
  /// [replaceStudents] true হলে সার্ভারের তালিকা এই ফোনের তালিকায় বদলে যায়।
  /// [force] true হলে "শুধু ওয়াইফাই" নিয়ম উপেক্ষা করা হয় (ম্যানুয়াল চাপ)।
  Future<SyncReport> syncNow({
    bool pull = true,
    bool uploadStudents = false,
    bool replaceStudents = false,
    bool force = false,
  }) async {
    if (_busy) return _lastReport ?? const SyncReport(note: 'সিঙ্ক চলছে…');
    if (!isConfigured) {
      _lastError = 'সার্ভারে লগইন করা নেই';
      _phase = SyncPhase.notConfigured;
      notifyListeners();
      return SyncReport(note: _lastError);
    }
    _busy = true;
    _lastError = '';
    final startedAt = DateTime.now().toIso8601String();
    final api = _api;
    var uploaded = 0, skipped = 0, failed = 0, noStudent = 0;
    var added = 0, updated = 0, conflicts = 0, pulledDocs = 0;
    var pulledStudents = 0;
    var note = '';

    try {
      // ---- ১. pull: সার্ভারের হালনাগাদ তালিকা/ডক-রেজিস্ট্রি ----
      if (pull) {
        _phase = SyncPhase.pulling;
        _status = 'সার্ভার থেকে তালিকা নামছে…';
        notifyListeners();
        final res = await api.pull(since: _settings.lastSyncAt);
        final st = await _db.applyServerStudents(res.students);
        added = st.added;
        updated = st.updated;
        conflicts = st.conflicts;
        pulledStudents = res.students.length;
        pulledDocs = await _db.applyServerDocuments(res.documents);
        if (res.now.isNotEmpty) {
          _settings.lastSyncAt = res.now;
          await _settings.save(_prefs);
        }
      }

      // ---- ২. admin: পুরো তালিকা সার্ভারে ----
      if (uploadStudents) {
        _status = 'তালিকা সার্ভারে পাঠানো হচ্ছে…';
        notifyListeners();
        final rows = await _db.getStudentsForUpload();
        final result = await _pushStudentsInChunks(api, rows, replaceStudents);
        note = 'তালিকা: ${result.upserted} টি ওঠেছে'
            '${result.deactivated > 0 ? ', ${result.deactivated} নিষ্ক্রিয়' : ''}'
            '${result.failed.isNotEmpty ? ', ব্যর্থ ${result.failed.length}' : ''}';
        if (result.upserted > 0) {
          await _db.markAllStudentsSynced(_settings.lastSyncAt);
        }
      }
    } on SyncApiException catch (e) {
      _lastError = e.message;
      if (e.isAuth) _status = 'সেশন শেষ — আবার লগইন করুন';
    } catch (e) {
      _lastError = 'সিঙ্ক ব্যর্থ: $e';
    }

    // ---- ৩. আপলোড আলাদা ধাপে — pull ব্যর্থ হলেও ফোনের ছবি পাঠানোর
    //         চেষ্টা হয় (নইলে নেট-ঝাঁকুনিতে ছবি দিনের পর দিন আটকে থাকত)।
    if (!_lastError.contains('সেশন শেষ')) {
      final up = await _uploadPending(api, force: force, startNote: note);
      uploaded = up.uploaded;
      skipped = up.skipped;
      failed = up.failed;
      noStudent = up.noStudent;
      note = up.note;
      if (up.error != null) _lastError = up.error!;
    }

    _busy = false;
    _phase = SyncPhase.idle;
    _status = '';
    try {
      await _db.addSyncLog(
        startedAt: startedAt,
        uploaded: uploaded,
        downloaded: pulledDocs,
        failed: failed + noStudent,
        note: [
          if (note.isNotEmpty) note,
          if (_lastError.isNotEmpty) _lastError,
          'added=$added updated=$updated conflicts=$conflicts skipped=$skipped',
        ].join(' | '),
      );
    } catch (_) {}
    await refresh();

    _lastReport = SyncReport(
      pulledStudents: pulledStudents,
      studentsAdded: added,
      studentsUpdated: updated,
      conflicts: conflicts,
      pulledDocs: pulledDocs,
      uploaded: uploaded,
      uploadSkipped: skipped,
      uploadFailed: failed,
      noStudent: noStudent,
      note: _lastError.isNotEmpty ? _lastError : (note.isEmpty ? null : note),
    );
    notifyListeners();
    return _lastReport!;
  }

  /// অপেক্ষমাণ (নতুন/ব্যর্থ) ডকুমেন্টগুলো সার্ভারে পাঠানো।
  /// প্রতি রাউন্ডে ২৫টি — একই ডক দুইবার চেষ্টা হয় না, তাই নেট-ঝাঁকুনিতে
  /// infinite loop হয় না।
  Future<_UploadResult> _uploadPending(SyncApi api,
      {required bool force, String startNote = ''}) async {
    var uploaded = 0, skipped = 0, failed = 0, noStudent = 0;
    var note = startNote;
    String? error;

    final wifiOk = force || !_settings.wifiOnly || await onWifi();
    if (!wifiOk) {
      final pending = _counts['pending'] ?? 0;
      if (pending > 0) {
        final msg = '"শুধু ওয়াইফাই" চালু — $pending টি ছবি আপলোড বাকি '
            '(ওয়াইফাই পেলে নিজেই যাবে)';
        return _UploadResult(note: note.isEmpty ? msg : '$note • $msg');
      }
      return _UploadResult(note: note);
    }

    _phase = SyncPhase.uploading;
    final attempted = <String>{};
    var round = 0;
    while (round++ < 200) {
      final all = await _db.getPendingDocs(limit: 25);
      final batch =
          all.where((d) => !attempted.contains(_docKey(d))).toList();
      if (batch.isEmpty) break;
      var stopAll = false;
      for (final doc in batch) {
        attempted.add(_docKey(doc));
        final file = File(doc.filePath);
        if (!await file.exists()) {
          await _db.markDocFailed(doc.dakhila, doc.type);
          failed++;
          continue;
        }
        final total = _counts['pending'] ?? 0;
        _status = 'ছবি পাঠানো হচ্ছে — দাখিলা ${doc.dakhila} '
            '(${doc.type.label}); বাকি প্রায় $total টি';
        notifyListeners();
        try {
          final res = await api.pushDoc(
            dakhila: doc.dakhila,
            docType: doc.type.name,
            file: file,
          );
          await _db.markDocSynced(
              doc.dakhila, doc.type, res.storagePath, _settings.email);
          if (res.skipped) {
            skipped++;
          } else {
            uploaded++;
          }
        } on SyncApiException catch (e) {
          if (e.code == 'NO_STUDENT') {
            await _db.markDocFailed(doc.dakhila, doc.type);
            noStudent++;
          } else if (e.isAuth) {
            error = 'সেশন শেষ — আবার লগইন করুন';
            stopAll = true;
            break;
          } else if (e.isNetwork) {
            // নেট গেল — ব্যর্থ হিসেবে চিহ্নিত নয়; পরের সুযোগে আবার চেষ্টা
            error = e.message;
            stopAll = true;
            break;
          } else {
            await _db.markDocFailed(doc.dakhila, doc.type);
            failed++;
          }
        }
      }
      if (stopAll) break;
    }
    return _UploadResult(
        uploaded: uploaded,
        skipped: skipped,
        failed: failed,
        noStudent: noStudent,
        note: note,
        error: error);
  }

  /// বড় তালিকা ৫০০ করে ভাগ করে পাঠানো (টাইমআউট/মেমরি সীমা এড়াতে)।
  Future<PushStudentsResult> _pushStudentsInChunks(
      SyncApi api, List<Map<String, dynamic>> rows, bool replace) async {
    var upserted = 0, skipped = 0, deactivated = 0;
    final failed = <String>[];
    const size = 500;
    for (var i = 0; i < rows.length; i += size) {
      final end = (i + size > rows.length) ? rows.length : i + size;
      // replace কেবল প্রথম চাঙ্কে — নইলে পরের চাঙ্কগুলো আগেরগুলোকে
      // "অ্যাপে নেই" ভেবে নিষ্ক্রিয় করে দিত।
      final res = await api.pushStudents(rows.sublist(i, end),
          replace: replace && i == 0);
      upserted += res.upserted;
      skipped += res.skipped;
      deactivated += res.deactivated;
      failed.addAll(res.failed);
      _status = 'তালিকা পাঠানো হচ্ছে… $upserted/${rows.length}';
      notifyListeners();
    }
    return PushStudentsResult(
        upserted: upserted,
        skipped: skipped,
        deactivated: deactivated,
        failed: failed);
  }

  static String _docKey(StudentDocument d) => '${d.dakhila}|${d.type.name}';

  /// এক ছাত্রের অপেক্ষমাণ ছবি সাথে সাথে পাঠানো (ছবি তোলার পরে ডাকার জন্য)।
  Future<bool> pushDocsFor(String dakhila) async {
    if (!isConfigured || _busy) return false;
    if (!await serverReachable()) return false;
    final api = _api;
    var ok = true;
    for (final doc in await _db.getPendingDocs(limit: 10)) {
      if (doc.dakhila != dakhila) continue;
      final file = File(doc.filePath);
      if (!await file.exists()) continue;
      try {
        final res = await api.pushDoc(
            dakhila: doc.dakhila, docType: doc.type.name, file: file);
        await _db.markDocSynced(
            doc.dakhila, doc.type, res.storagePath, _settings.email);
      } catch (_) {
        ok = false;
      }
    }
    await refresh();
    return ok;
  }
}

/// আপলোড-ধাপের ভেতরের ফল (SyncReport-এ বসিয়ে দেওয়া হয়)।
class _UploadResult {
  final int uploaded;
  final int skipped;
  final int failed;
  final int noStudent;
  final String note;
  final String? error;
  const _UploadResult({
    this.uploaded = 0,
    this.skipped = 0,
    this.failed = 0,
    this.noStudent = 0,
    this.note = '',
    this.error,
  });
}
