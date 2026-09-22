import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/sync_models.dart';

/// সার্ভার-কল ব্যর্থ হলে ছোঁড়া হয়। [status] = HTTP কোড (0 = নেটওয়ার্ক/টাইমআউট)।
class SyncApiException implements Exception {
  final int status;
  final String code;
  final String message;

  const SyncApiException(this.status, this.code, this.message);

  bool get isNetwork => status == 0;

  /// টোকেন আর বৈধ নয় (আবার লগইন দরকার)।
  bool get isAuth => status == 401;

  @override
  String toString() => message.isEmpty ? '$code ($status)' : message;
}

/// S2: XAMPP-এ চালানো dakhila REST API-র সরল ক্লায়েন্ট।
///
/// ইচ্ছাকৃতভাবে `dart:io` HttpClient — অ্যাপে কোনো নতুন HTTP প্যাকেজ যোগ
/// করতে হয় না; আর এতে মাল্টিপার্ট আপলোড নিজের হাতে নিয়ন্ত্রিত থাকে।
class SyncApi {
  /// হোস্ট-রুট (`http://ip/dakhila`) — শেষের `/` বা `/api` বাদ দিয়ে।
  final String baseUrl;

  /// Bearer টোকেন — লগইনের পরে সেট হয়।
  String token;

  SyncApi({required String baseUrl, this.token = ''})
      : baseUrl = normalizeBase(baseUrl);

  /// ব্যবহারকারীর লেখা ঠিকানা থেকে হোস্ট-রুট — `192.168.0.5/dakhila`,
  /// `http://192.168.0.5/dakhila/`, `.../dakhila/api` সবই এক হয়।
  static String normalizeBase(String input) {
    var s = input.trim();
    if (s.isEmpty) return '';
    if (!s.startsWith('http://') && !s.startsWith('https://')) {
      s = 'http://$s';
    }
    if (s.endsWith('/')) s = s.substring(0, s.length - 1);
    if (s.endsWith('/api')) s = s.substring(0, s.length - 4);
    return s;
  }

  Uri _uri(String file, [Map<String, String>? query]) {
    final u = Uri.parse('$baseUrl/api/$file');
    return query == null ? u : u.replace(queryParameters: query);
  }

  /// এককালীন HttpClient — কল শেষে বন্ধ করা হয় (লিক নয়)।
  HttpClient _client(int timeoutMs) {
    return HttpClient()
      ..connectionTimeout = Duration(milliseconds: timeoutMs)
      ..idleTimeout = const Duration(seconds: 5);
  }

  Future<Map<String, dynamic>> _json(
    String method,
    String file, {
    Map<String, String>? query,
    Object? body,
    int timeoutMs = 20000,
  }) async {
    if (baseUrl.isEmpty) {
      throw const SyncApiException(0, 'NO_SERVER', 'সার্ভারের ঠিকানা দেওয়া হয়নি');
    }
    final client = _client(timeoutMs);
    final limit = Duration(milliseconds: timeoutMs);
    try {
      final req = await client.openUrl(method, _uri(file, query)).timeout(limit);
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (token.isNotEmpty) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      if (body != null) {
        final bytes = utf8.encode(jsonEncode(body));
        req.headers.set(
            HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
        req.headers.contentLength = bytes.length;
        req.add(bytes);
      }
      final res = await req.close().timeout(limit);
      final text =
          await res.transform(utf8.decoder).join().timeout(limit);
      return _decode(res.statusCode, text);
    } on SyncApiException {
      rethrow;
    } on TimeoutException {
      throw const SyncApiException(0, 'TIMEOUT', 'সার্ভার সাড়া দিচ্ছে না');
    } on SocketException catch (e) {
      throw SyncApiException(
          0, 'NETWORK', 'সংযোগ ব্যর্থ: ${e.osError?.message ?? e.message}');
    } catch (e) {
      throw SyncApiException(0, 'IO', 'সংযোগ সমস্যা: $e');
    } finally {
      client.close(force: true);
    }
  }

  /// রেসপন্স-বডি → map; `ok:false` বা 4xx/5xx হলে SyncApiException ছোঁড়ে।
  Map<String, dynamic> _decode(int status, String text) {
    Map<String, dynamic> map;
    try {
      final decoded =
          text.trim().isEmpty ? <String, dynamic>{} : jsonDecode(text);
      map = decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{'raw': decoded};
    } catch (_) {
      throw SyncApiException(status, 'BAD_JSON', 'সার্ভারের উত্তর বোঝা গেল না');
    }
    if (status >= 400 || map['ok'] == false) {
      throw SyncApiException(
        status,
        (map['error'] as String?) ?? 'HTTP_$status',
        (map['message'] as String?) ?? 'সার্ভার ত্রুটি ($status)',
      );
    }
    return map;
  }

  static List<Map<String, dynamic>> _rows(Object? raw) {
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((r) => r.cast<String, dynamic>()).toList();
  }

  // ---------------------------------------------------------------------
  // endpoint-ভিত্তিক মেথড
  // ---------------------------------------------------------------------

  /// সার্ভার সচল কি না (লগইন ছাড়াই) — সেটিংসের "সংযোগ পরীক্ষা"।
  Future<PingResult> ping() async {
    final m = await _json('GET', 'ping.php', timeoutMs: 12000);
    return PingResult(
      ok: m['ok'] == true,
      dbOk: m['db'] == true,
      students: (m['students'] as num?)?.toInt() ?? 0,
      time: '${m['time'] ?? ''}',
    );
  }

  Future<LoginResult> login(String email, String password) async {
    final m = await _json('POST', 'login.php',
        body: {'email': email, 'password': password});
    return LoginResult(
      token: '${m['token'] ?? ''}',
      name: '${m['name'] ?? ''}',
      role: '${m['role'] ?? 'teacher'}',
    );
  }

  /// `since` (সার্ভার-সময়) দিলে কেবল তার পরের পরিবর্তন আসে; null = সব।
  Future<PullResult> pull({String? since}) async {
    final m = await _json('GET', 'pull.php',
        query: (since == null || since.isEmpty) ? null : {'since': since},
        timeoutMs: 90000);
    return PullResult(
      now: '${m['now'] ?? ''}',
      students: _rows(m['students']),
      documents: _rows(m['documents']),
    );
  }

  /// admin-এর তালিকা আপলোড (JSON)।
  Future<PushStudentsResult> pushStudents(List<Map<String, dynamic>> rows,
      {bool replace = false}) async {
    final m = await _json('POST', 'push_students.php',
        body: {'students': rows, 'replace': replace}, timeoutMs: 180000);
    final failed = <String>[];
    final raw = m['failed'];
    if (raw is List) {
      for (final f in raw) {
        if (f is Map && f['dakhila'] != null) failed.add('${f['dakhila']}');
      }
    }
    return PushStudentsResult(
      upserted: (m['upserted'] as num?)?.toInt() ?? 0,
      skipped: (m['skipped'] as num?)?.toInt() ?? 0,
      deactivated: (m['deactivated'] as num?)?.toInt() ?? 0,
      failed: failed,
    );
  }

  /// একটি ডকুমেন্ট (ছবি) আপলোড — multipart/form-data হাতে বানিয়ে।
  /// সার্ভার নিজেই ফাইলের sha256 হিসাব করে (ক্লায়েন্টের মান বিশ্বাস করে না)।
  Future<PushDocResult> pushDoc({
    required String dakhila,
    required String docType,
    required File file,
    int timeoutMs = 120000,
  }) async {
    if (baseUrl.isEmpty) {
      throw const SyncApiException(0, 'NO_SERVER', 'সার্ভারের ঠিকানা দেওয়া হয়নি');
    }
    if (!await file.exists()) {
      throw const SyncApiException(0, 'NO_FILE', 'ফাইল খুঁজে পাওয়া যায়নি');
    }
    final ext = file.path.contains('.')
        ? file.path.split('.').last.toLowerCase()
        : 'jpg';
    final mime = ext == 'png'
        ? 'image/png'
        : (ext == 'pdf' ? 'application/pdf' : 'image/jpeg');
    final bytes = await file.readAsBytes();
    final boundary =
        '----dakhila${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';

    final head = StringBuffer();
    void field(String name, String value) {
      head.write('--$boundary\r\n');
      head.write('Content-Disposition: form-data; name="$name"\r\n\r\n');
      head.write('$value\r\n');
    }

    field('dakhila', dakhila);
    field('doc_type', docType);
    head.write('--$boundary\r\n');
    head.write(
        'Content-Disposition: form-data; name="file"; filename="$dakhila.$ext"\r\n');
    head.write('Content-Type: $mime\r\n\r\n');
    final tail = '\r\n--$boundary--\r\n';

    final bodyBytes = <int>[
      ...utf8.encode(head.toString()),
      ...bytes,
      ...utf8.encode(tail),
    ];

    final client = _client(timeoutMs);
    final limit = Duration(milliseconds: timeoutMs);
    try {
      final req = await client
          .openUrl('POST', _uri('push_doc.php'))
          .timeout(limit);
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (token.isNotEmpty) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      req.headers.set(HttpHeaders.contentTypeHeader,
          'multipart/form-data; boundary=$boundary');
      req.headers.contentLength = bodyBytes.length;
      req.add(bodyBytes);
      final res = await req.close().timeout(limit);
      final text = await res.transform(utf8.decoder).join().timeout(limit);
      final map = _decode(res.statusCode, text);
      return PushDocResult(
        skipped: map['skipped'] == true,
        storagePath: '${map['storage_path'] ?? ''}',
      );
    } on SyncApiException {
      rethrow;
    } on TimeoutException {
      throw const SyncApiException(0, 'TIMEOUT', 'আপলোড টাইমআউট');
    } on SocketException catch (e) {
      throw SyncApiException(
          0, 'NETWORK', 'সংযোগ ব্যর্থ: ${e.osError?.message ?? e.message}');
    } catch (e) {
      throw SyncApiException(0, 'IO', 'আপলোড ব্যর্থ: $e');
    } finally {
      client.close(force: true);
    }
  }
}