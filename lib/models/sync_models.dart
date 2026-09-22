import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// S2: সার্ভার-সিঙ্ক সেটিংস (shared_preferences-এ সংরক্ষিত)।
///
/// অ্যাপ কখনো ইন্টারনেট-বাধ্য নয় — এই সেটিংস খালি থাকলে অ্যাপ আগের মতোই
/// ১০০% অফলাইনে চলে, শুধু "সিঙ্ক" অংশটি নিষ্ক্রিয় থাকে।
class SyncSettings {
  /// সার্ভারের হোস্ট-রুট — যেমন `http://192.168.0.10/dakhila`
  /// (শেষে `/api` দিলেও চলে; নরমালাইজ করে নেওয়া হয়)।
  String serverUrl;

  /// লগইন করা শিক্ষকের ইমেইল (শূন্য হলে লগইন হয়নি)।
  String email;
  String token;
  String teacherName;

  /// 'admin' হলে তালিকা আপলোড/যাচাইয়ের অনুমতি।
  String role;

  /// এই ফোনের স্থায়ী পরিচয় — একবার বানিয়ে সার্ভারে পাঠানো হয়।
  String deviceId;

  /// শেষ সফল pull-এর সার্ভার-সময় (delta sync-এর `since`)।
  String? lastSyncAt;

  /// অ্যাপ চালু/তালিকায় ফেরার সময় নিজে নিজে সিঙ্ক করার অনুমতি।
  bool autoSync;

  /// শুধু-ওয়াইফাই আপলোড (মাদ্রাসার মোবাইল-ডেটা বাঁচাতে ডিফল্ট: true)।
  bool wifiOnly;

  SyncSettings({
    this.serverUrl = '',
    this.email = '',
    this.token = '',
    this.teacherName = '',
    this.role = 'teacher',
    this.deviceId = '',
    this.lastSyncAt,
    this.autoSync = true,
    this.wifiOnly = true,
  });

  /// লগইন সম্পূর্ণ (সার্ভার + টোকেন দুটোই আছে) — তবেই সিঙ্ক চালু।
  bool get isLoggedIn => serverUrl.isNotEmpty && token.isNotEmpty;

  bool get isAdmin => role == 'admin';

  factory SyncSettings.load(SharedPreferences prefs) {
    return SyncSettings(
      serverUrl: prefs.getString(_kServerUrl) ?? '',
      email: prefs.getString(_kEmail) ?? '',
      token: prefs.getString(_kToken) ?? '',
      teacherName: prefs.getString(_kTeacherName) ?? '',
      role: prefs.getString(_kRole) ?? 'teacher',
      deviceId: prefs.getString(_kDeviceId) ?? '',
      lastSyncAt: prefs.getString(_kLastSyncAt),
      autoSync: prefs.getBool(_kAutoSync) ?? true,
      wifiOnly: prefs.getBool(_kWifiOnly) ?? true,
    );
  }

  Future<void> save(SharedPreferences prefs) async {
    await prefs.setString(_kServerUrl, serverUrl);
    await prefs.setString(_kEmail, email);
    await prefs.setString(_kToken, token);
    await prefs.setString(_kTeacherName, teacherName);
    await prefs.setString(_kRole, role);
    await prefs.setString(_kDeviceId, deviceId);
    if (lastSyncAt != null) await prefs.setString(_kLastSyncAt, lastSyncAt!);
    await prefs.setBool(_kAutoSync, autoSync);
    await prefs.setBool(_kWifiOnly, wifiOnly);
  }

  /// লগআউট — সার্ভার-টোকেন মুছে ফেলে (সার্ভার-ঠিকানা/পছন্দ থাকে)।
  Future<void> clearSession(SharedPreferences prefs) async {
    token = '';
    email = '';
    teacherName = '';
    role = 'teacher';
    lastSyncAt = null;
    await prefs.remove(_kToken);
    await prefs.remove(_kEmail);
    await prefs.remove(_kTeacherName);
    await prefs.remove(_kRole);
    await prefs.remove(_kLastSyncAt);
  }

  /// এই ফোনের জন্য স্থায়ী ডিভাইস-আইডি (একবার তৈরি, তারপর অপরিবর্তিত)।
  static Future<String> ensureDeviceId(SharedPreferences prefs) async {
    final old = prefs.getString(_kDeviceId);
    if (old != null && old.isNotEmpty) return old;
    final rand = Random.secure();
    final bytes = List<int>.generate(8, (_) => rand.nextInt(256));
    final id =
        'dev-${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
    await prefs.setString(_kDeviceId, id);
    return id;
  }

  static const _kServerUrl = 'sync.serverUrl';
  static const _kEmail = 'sync.email';
  static const _kToken = 'sync.token';
  static const _kTeacherName = 'sync.teacherName';
  static const _kRole = 'sync.role';
  static const _kDeviceId = 'sync.deviceId';
  static const _kLastSyncAt = 'sync.lastSyncAt';
  static const _kAutoSync = 'sync.autoSync';
  static const _kWifiOnly = 'sync.wifiOnly';
}

/// ping.php-এর রেসপন্স — সার্ভার/ডাটাবেজ সচল কি না।
class PingResult {
  final bool ok;
  final bool dbOk;
  final int students;
  final String time;
  const PingResult({
    required this.ok,
    required this.dbOk,
    required this.students,
    required this.time,
  });
}

/// login.php-এর রেসপন্স।
class LoginResult {
  final String token;
  final String name;
  final String role;
  const LoginResult({
    required this.token,
    required this.name,
    required this.role,
  });
}

/// pull.php-এর রেসপন্স — সার্ভারের হালনাগাদ সারি + server-time।
class PullResult {
  final String now;
  final List<Map<String, dynamic>> students;
  final List<Map<String, dynamic>> documents;
  const PullResult({
    required this.now,
    required this.students,
    required this.documents,
  });
}

/// push_doc.php-এর রেসপন্স। [skipped] = একই ছবি (sha256) আগেই সার্ভারে আছে।
class PushDocResult {
  final bool skipped;
  final String storagePath;
  const PushDocResult({required this.skipped, required this.storagePath});
}

/// push_students.php-এর রেসপন্স।
class PushStudentsResult {
  final int upserted;
  final int skipped;
  final int deactivated;
  final List<String> failed;
  const PushStudentsResult({
    required this.upserted,
    required this.skipped,
    required this.deactivated,
    required this.failed,
  });
}

/// এক সিঙ্ক-সেশনের ফল — UI-তে দেখানো হয়।
class SyncReport {
  final int pulledStudents;
  final int studentsAdded;
  final int studentsUpdated;
  final int conflicts;
  final int pulledDocs;
  final int uploaded;
  final int uploadSkipped;
  final int uploadFailed;
  final int noStudent;
  final String? note;

  const SyncReport({
    this.pulledStudents = 0,
    this.studentsAdded = 0,
    this.studentsUpdated = 0,
    this.conflicts = 0,
    this.pulledDocs = 0,
    this.uploaded = 0,
    this.uploadSkipped = 0,
    this.uploadFailed = 0,
    this.noStudent = 0,
    this.note,
  });

  bool get isEmpty =>
      pulledStudents == 0 &&
      uploaded == 0 &&
      uploadSkipped == 0 &&
      uploadFailed == 0 &&
      conflicts == 0;

  /// সংক্ষিপ্ত এক-লাইন সারাংশ (সিঙ্ক-স্ক্রিন/স্ন্যাকবার)।
  String get summary {
    final parts = <String>[];
    if (studentsAdded > 0) parts.add('নতুন $studentsAdded জন');
    if (studentsUpdated > 0) parts.add('আপডেট $studentsUpdated');
    if (uploaded > 0) parts.add('ছবি আপলোড $uploaded');
    if (uploadSkipped > 0) parts.add('আগেই ছিল $uploadSkipped');
    if (noStudent > 0) parts.add('সার্ভারে নেই $noStudent');
    if (uploadFailed > 0) parts.add('ব্যর্থ $uploadFailed');
    if (conflicts > 0) parts.add('দ্বন্দ্ব $conflicts');
    if (note != null && note!.isNotEmpty) parts.add(note!);
    return parts.isEmpty ? 'সব সিঙ্ক হয়ে আছে ✓' : parts.join(' • ');
  }
}