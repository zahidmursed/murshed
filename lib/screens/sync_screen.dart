import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/sync_api.dart';
import '../services/sync_service.dart';

/// S2: ক্লাউড সিঙ্ক স্ক্রিন — লগইন, অবস্থা, ম্যানুয়াল সি্ক ও admin-তালিকা আপলোড।
///
/// অফলাইন-ফার্স্ট নীতি: কখনো লগইন করতে বাধ্য নয়। লগইন না করলে এখানে
/// শুধু ফর্ম দেখায়; অ্যাপের বাকি সব কাজ আগের মতোই চলে।
class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  final _urlCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  bool _obscure = true;
  bool _testing = false;
  bool _loggingIn = false;
  bool _uploadOld = true;
  bool _replaceStudents = false;
  String _message = '';
  bool _messageOk = true;

  @override
  void initState() {
    super.initState();
    final s = context.read<SyncService>().settings;
    _urlCtrl.text = s.serverUrl;
    _emailCtrl.text = s.email;
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  void _setMessage(String text, {bool ok = true}) {
    if (!mounted) return;
    setState(() {
      _message = text;
      _messageOk = ok;
    });
  }

  /// সংযোগ পরীক্ষা — ping.php (লগইন ছাড়াই)।
  Future<void> _test() async {
    setState(() {
      _testing = true;
      _message = '';
    });
    try {
      final res = await context.read<SyncService>().testConnection(_urlCtrl.text);
      _setMessage(
          'সার্ভার ঠিক আছে ✓ (ডাটাবেজ: ${res.dbOk ? "সচল" : "ত্রুটি"}, '
          'সার্ভারে ${res.students} জন)',
          ok: res.dbOk);
    } on SyncApiException catch (e) {
      _setMessage(e.message, ok: false);
    } catch (e) {
      _setMessage('সংযোগ ব্যর্থ: $e', ok: false);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _login() async {
    if (_urlCtrl.text.trim().isEmpty ||
        _emailCtrl.text.trim().isEmpty ||
        _passCtrl.text.isEmpty) {
      _setMessage('সার্ভারের ঠিকানা, ইমেইল ও পাসওয়ার্ড — তিনটিই দিন',
          ok: false);
      return;
    }
    setState(() {
      _loggingIn = true;
      _message = '';
    });
    try {
      final res = await context.read<SyncService>().login(
            rawUrl: _urlCtrl.text,
            email: _emailCtrl.text,
            password: _passCtrl.text,
          );
      _passCtrl.clear();
      _setMessage('লগইন সফল ✓ (${res.name} — ${res.role == 'admin' ? "প্রধান" : "শিক্ষক"})');
    } on SyncApiException catch (e) {
      _setMessage(e.isAuth ? 'ইমেইল বা পাসওয়ার্ড ভুল' : e.message, ok: false);
    } catch (e) {
      _setMessage('লগইন ব্যর্থ: $e', ok: false);
    } finally {
      if (mounted) setState(() => _loggingIn = false);
    }
  }

  Future<void> _runSync({required bool uploadStudents}) async {
    final svc = context.read<SyncService>();
    await svc.syncNow(
      uploadStudents: uploadStudents,
      replaceStudents: uploadStudents && _replaceStudents,
      force: true, // ইউজার নিজে চাপ দিয়েছেন — শুধু-ওয়াইফাই নিয়ম শিথিল
    );
    final r = svc.lastReport;
    _setMessage(
      r == null
          ? 'সিঙ্ক হয়েছে'
          : (svc.lastError.isNotEmpty ? svc.lastError : r.summary),
      ok: svc.lastError.isEmpty,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ক্লাউড সিঙ্ক'),
        backgroundColor: Colors.teal,
      ),
      body: Consumer<SyncService>(
        builder: (context, sync, _) {
          final s = sync.settings;
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              if (_message.isNotEmpty) _messageCard(),
              if (!s.isLoggedIn) _loginCard(sync),
              if (s.isLoggedIn) ...[
                _statusCard(sync),
                _uploadCard(sync),
                const SizedBox(height: 12),
                _logsCard(sync),
              ],
              const SizedBox(height: 12),
              _helpCard(),
            ],
          );
        },
      ),
    );
  }

  Widget _messageCard() => Card(
        color: _messageOk ? Colors.teal.shade50 : Colors.red.shade50,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Icon(_messageOk ? Icons.check_circle : Icons.error_outline,
                color: _messageOk ? Colors.teal : Colors.red),
            const SizedBox(width: 8),
            Expanded(child: Text(_message, style: const TextStyle(fontSize: 13))),
          ]),
        ),
      );

  Widget _sectionTitle(IconData icon, String text, Color color) => Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 8),
          Text(text,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      );

  /// লগইন কার্ড — সার্ভারের ঠিকানা + শিক্ষকের ইমেইল/পাসওয়ার্ড।
  Widget _loginCard(SyncService sync) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle(Icons.cloud_outlined, 'সার্ভারে লগইন', Colors.teal),
              const SizedBox(height: 6),
              const Text(
                'স্কুলের কম্পিউটারে XAMPP চালু থাকতে হবে (Apache + MySQL)। '
                'একই ওয়াইফাইতে থাকলে সার্ভারের ঠিকানা দিন — যেমন '
                'http://192.168.0.10/dakhila',
                style: TextStyle(fontSize: 11, color: Colors.black54),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _urlCtrl,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'সার্ভারের ঠিকানা',
                  hintText: 'http://192.168.0.10/dakhila',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'ইমেইল',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _passCtrl,
                obscureText: _obscure,
                onSubmitted: (_) => _loggingIn ? null : _login(),
                decoration: InputDecoration(
                  labelText: 'পাসওয়ার্ড',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: IconButton(
                    icon: Icon(
                        _obscure ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _testing ? null : _test,
                      icon: _testing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.network_check),
                      label: const Text('সংযোগ পরীক্ষা'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _loggingIn ? null : _login,
                      icon: _loggingIn
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.login),
                      label: const Text('লগইন'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

  /// অবস্থা কার্ড — কে লগইন, কত বাকি, শেষ সিঙ্ক কবে, ম্যানুয়াল বোতাম।
  Widget _statusCard(SyncService sync) {
    final s = sync.settings;
    final pending = sync.pendingDocs;
    final busy = sync.isBusy;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(Icons.cloud_done, 'সিঙ্ক অবস্থা', Colors.teal),
            const SizedBox(height: 8),
            Text(
              '${s.teacherName.isEmpty ? s.email : s.teacherName} '
              '(${s.isAdmin ? "প্রধান" : "শিক্ষক"})',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            Text(s.serverUrl,
                style: const TextStyle(fontSize: 11, color: Colors.black54)),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color:
                    pending > 0 ? Colors.orange.shade50 : Colors.teal.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                pending > 0
                    ? '$pending টি ছবি Sync বাকি'
                    : (sync.counts['total'] == 0
                        ? 'এখনো কোনো ছবি তোলা হয়নি'
                        : 'সব ছবি Sync হয়ে আছে ✓'),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: pending > 0 ? Colors.orange.shade900 : Colors.teal,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'মোট ${sync.counts['total'] ?? 0} • পাঠানো হয়েছে '
              '${sync.counts['synced'] ?? 0} • বাকি $pending • ব্যর্থ '
              '${sync.counts['failed'] ?? 0} • বাদ '
              '${sync.counts['skipped'] ?? 0}',
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
            if (busy) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
              const SizedBox(height: 4),
              Text(sync.status.isEmpty ? 'কাজ চলছে…' : sync.status,
                  style: const TextStyle(fontSize: 11)),
            ],
            if (sync.lastError.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(sync.lastError,
                  style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
            ],
            if (s.lastSyncAt != null) ...[
              const SizedBox(height: 4),
              Text('শেষ সিঙ্ক: ${_displayTime(s.lastSyncAt!)}',
                  style: const TextStyle(fontSize: 11, color: Colors.black54)),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed:
                        busy ? null : () => _runSync(uploadStudents: false),
                    icon: const Icon(Icons.sync),
                    label: const Text('এখন সিঙ্ক করুন'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : _logout,
                    icon: const Icon(Icons.logout),
                    label: const Text('লগআউট'),
                  ),
                ),
              ],
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: s.autoSync,
              onChanged: sync.setAutoSync,
              title: const Text('নিজে নিজে সিঙ্ক', style: TextStyle(fontSize: 13)),
              subtitle: const Text('অ্যাপ খুললেই সুযোগ পেলে মিলিয়ে নেবে',
                  style: TextStyle(fontSize: 11)),
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: s.wifiOnly,
              onChanged: sync.setWifiOnly,
              title: const Text('শুধু ওয়াইফাইতে ছবি পাঠাও',
                  style: TextStyle(fontSize: 13)),
              subtitle: const Text('মোবাইল ডেটা খরচ বাঁচাতে (সুপারিশ)',
                  style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
      ),
    );
  }

  /// "2026-09-19T10:20:31" → "19/09/2026 10:20"
  static String _displayTime(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    String p(int v) => v.toString().padLeft(2, '0');
    return '${p(d.day)}/${p(d.month)}/${d.year} ${p(d.hour)}:${p(d.minute)}';
  }

  Future<void> _logout() async {
    await context.read<SyncService>().logout();
    _setMessage('লগআউট হয়েছে — অ্যাপ আগের মতোই অফলাইনে চলবে');
  }

  /// তালিকা/পুরনো ছবি সংক্রান্ত কার্ড (admin-এর জন্য তালিকা পাঠানো)।
  Widget _uploadCard(SyncService sync) {
    final busy = sync.isBusy;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(Icons.cloud_upload, 'আপলোডের নিয়ম', Colors.indigo),
            const SizedBox(height: 6),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _uploadOld,
              onChanged: busy ? null : (v) => setState(() => _uploadOld = v),
              title: const Text('পুরনো সব ছবিও সার্ভারে যাবে',
                  style: TextStyle(fontSize: 13)),
              subtitle: const Text('বন্ধ রাখলে শুধু নতুন তোলা ছবি যাবে',
                  style: TextStyle(fontSize: 11)),
            ),
            OutlinedButton.icon(
              onPressed: busy
                  ? null
                  : () async {
                      await sync.setUploadOldPhotos(_uploadOld);
                      _setMessage(sync.status);
                    },
              icon: const Icon(Icons.tune),
              label: const Text('এই নিয়ম প্রয়োগ করুন'),
            ),
            if (sync.settings.isAdmin) ...[
              const Divider(),
              _sectionTitle(
                  Icons.groups, 'ছাত্র-তালিকা (প্রধানের জন্য)', Colors.brown),
              const SizedBox(height: 6),
              const Text(
                'ফোনে ইমপোর্ট করা তালিকা সার্ভারে তুলে দিলে সব শিক্ষকের ফোনে '
                'চলে যাবে — phpMyAdmin/CSV-র দরকার নেই।',
                style: TextStyle(fontSize: 11, color: Colors.black54),
              ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _replaceStudents,
                onChanged:
                    busy ? null : (v) => setState(() => _replaceStudents = v),
                title: const Text(
                    'সার্ভারের তালিকা এই ফোনের তালিকায় বদলে যাবে',
                    style: TextStyle(fontSize: 13)),
                subtitle: const Text(
                    'বন্ধ রাখলে সার্ভারের তালিকা নামবে ও মিলে যাবে (নিরাপদ)',
                    style: TextStyle(fontSize: 11)),
              ),
              FilledButton.tonalIcon(
                onPressed: busy ? null : () => _runSync(uploadStudents: true),
                icon: const Icon(Icons.upload_file),
                label: const Text('তালিকা সার্ভারে পাঠান + সিঙ্ক'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// শেষ কয়েকটি সিঙ্ক-সেশনের হিসাব।
  Widget _logsCard(SyncService sync) {
    final logs = sync.recentLogs;
    if (logs.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(Icons.history, 'সি্ক-ইতিহাস', Colors.blueGrey),
            const SizedBox(height: 4),
            for (final l in logs)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text(
                  '${_displayTime('${l['started_at'] ?? ''}')} — '
                  'আপলোড ${l['uploaded'] ?? 0}, নামানো ${l['downloaded'] ?? 0}'
                  '${((l['failed'] as num?)?.toInt() ?? 0) > 0 ? ", ব্যর্থ ${l['failed']}" : ''}',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// সাধারণ ব্যাখ্যা — ইউজার যেন কখনো বিভ্রান্ত না হন।
  Widget _helpCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle(
                  Icons.help_outline, 'কীভাবে কাজ করে', Colors.blueGrey),
              const SizedBox(height: 6),
              const Text(
                '১. ইন্টারনেট না থাকলেও অ্যাপ পুরোপুরি চলে — ছবি ফোনে জমা হয়।\n'
                '২. অফিসের কম্পিউটার/সার্ভারে পৌঁছাতে পারলেই ছবি নিজে নিজে '
                'আপলোড হয়ে যায় (ওয়াইফাই পেলে)।\n'
                '৩. সার্ভারে ছাত্রের নাম/ক্লাস ঠিক করা হলে সব ফোনে তা চলে যায় '
                '— নতুন করে JSON/Excel ইমপোর্টের দরকার নেই।\n'
                '৪. কোন ছবি কার তোলা — সব সার্ভারে আলাদা করে জমা থাকে; '
                'একই দাখিলায় দুইজন একসাথে কাজ করলেও সমস্যা হয় না।',
                style: TextStyle(fontSize: 12, color: Colors.black87),
              ),
            ],
          ),
        ),
      );
}