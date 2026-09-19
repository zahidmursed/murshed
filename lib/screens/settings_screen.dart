import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../models/document.dart';
import '../providers/student_provider.dart';
import '../services/backup_service.dart';
import '../services/storage_service.dart';
import '../utils/case_notes_guard.dart';
import '../utils/image_processor.dart';
import 'teacher_manage_screen.dart';

/// সেটিংস: কাস্টম JSON ইমপোর্ট, ডেটা রিসেট, আউটপুট ফোল্ডার।
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _importing = false;
  bool _backingUp = false;
  bool _recovering = false;
  bool _migrating = false;
  bool _logoBusy = false;
  bool _folderBusy = false;
  bool _folderCancel = false;
  bool _dbBackupBusy = false;
  bool _dbRestoreBusy = false;
  String _dbBackupMsg = '';
  String _dbRestoreMsg = '';
  String _folderStatus = '';
  String _backupStatus = '';
  String _recoverStatus = '';
  String _migrateStatus = '';
  String _folderPath = '';

  @override
  void initState() {
    super.initState();
    _loadFolderPath();
  }

  Future<void> _loadFolderPath() async {
    final appDir = await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    if (mounted) {
      setState(() => _folderPath = '${appDir.path}/DakhilaCamera');
    }
  }

  Future<void> _importData({
    required List<String> extensions,
    required String label,
    required Future<int> Function(String path) run,
  }) async {
    final List<PlatformFile> files;
    try {
      files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: extensions,
      );
    } catch (e) {
      debugPrint('Pick file error: $e');
      return; // বাতিল/ব্যর্থ
    }
    final path = files.isEmpty ? null : files.single.path;
    if (path == null) return; // কোনো ফাইল নির্বাচিত হয়নি
    if (!mounted) return;
    setState(() => _importing = true);
    try {
      final imported = await run(path);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$imported টি রেকর্ড ইমপোর্ট হয়েছে ✓')),
      );
    } catch (e) {
      debugPrint('Import error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$label ব্যর্থ — ফাইল ফরম্যাট যাচাই করুন')),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _importJson() {
    final provider = context.read<StudentProvider>();
    return _importData(
      extensions: ['json'],
      label: 'JSON ইমপোর্ট',
      run: provider.importFromJsonFile,
    );
  }

  Future<void> _importExcel() {
    final provider = context.read<StudentProvider>();
    return _importData(
      extensions: ['xlsx'],
      label: 'Excel ইমপোর্ট',
      run: provider.importFromExcelFile,
    );
  }

  /// ফেজ C: Excel রাউন্ড-ট্রিপ — এক্সপোর্ট করা ফাইলের অ-খালি সেল দিয়ে আপডেট।
  Future<void> _importRoundTrip() {
    final provider = context.read<StudentProvider>();
    return _importData(
      extensions: ['xlsx'],
      label: 'Excel রাউন্ড-ট্রিপ আপডেট',
      run: (path) => provider
          .importStudentUpdatesFromXlsx(path)
          .then((r) => r.applied),
    );
  }

  /// ফেজ C: এক-ট্যাপ পূর্ণ ব্যাকআপ (DB + v2 ফাইল + লোগো → ZIP)।
  Future<void> _fullBackup() async {
    final provider = context.read<StudentProvider>();
    setState(() {
      _dbBackupBusy = true;
      _dbBackupMsg = 'ব্যাকআপ হচ্ছে...';
    });
    try {
      final path = await BackupService.backup(
        institutionName: provider.institutionName,
        onProgress: (done, total) {
          if (mounted) {
            setState(
                () => _dbBackupMsg = 'ব্যাকআপ হচ্ছে... $done/$total ফাইল');
          }
        },
      );
      if (!mounted) return;
      setState(() => _dbBackupMsg = '✅ সেভ হয়েছে: $path');
    } catch (e) {
      debugPrint('Backup failed: $e');
      if (!mounted) return;
      setState(() => _dbBackupMsg = '❌ ব্যাকআপ ব্যর্থ: $e');
    } finally {
      if (mounted) setState(() => _dbBackupBusy = false);
    }
  }

  /// ফেজ C: ZIP থেকে পূর্ণ পুনরুদ্ধার (বিপজ্জনক — দ্বিতীয় নিশ্চিতকরণসহ)।
  Future<void> _fullRestore() async {
    final provider = context.read<StudentProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    final path = files.isEmpty ? null : files.single.path;
    if (path == null) return;
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('সবকিছু পুনরুদ্ধার করবেন?'),
        content: const Text(
            'বর্তমান ডেটাবেস ও ছবি/ডকুমেন্ট ব্যাকআপের কনটেন্ট দিয়ে '
            'সম্পূর্ণ বদলে যাবে। এটা পরে বাতিল করা যাবে না।'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('বাতিল')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('পুনরুদ্ধার করুন')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _dbRestoreBusy = true;
      _dbRestoreMsg = 'শুরু হচ্ছে...';
    });
    try {
      final res = await BackupService.restore(
        zipPath: path,
        institutionName: provider.institutionName,
        onStep: (step) {
          if (mounted) setState(() => _dbRestoreMsg = step);
        },
      );
      if (res.institutionName != null &&
          res.institutionName!.isNotEmpty &&
          res.institutionName != provider.institutionName) {
        provider.setInstitutionName(res.institutionName!);
      }
      await provider.load();
      if (!mounted) return;
      setState(() => _dbRestoreMsg =
          '✅ সম্পন্ন — ${res.students} জন ছাত্র, ${res.files} ফাইল');
      messenger.showSnackBar(SnackBar(
          content: Text(
              '✅ পুনরুদ্ধার সম্পন্ন: ${res.students} জন ছাত্র + ${res.files} ফাইল')));
    } catch (e) {
      debugPrint('Restore failed: $e');
      if (!mounted) return;
      setState(() => _dbRestoreMsg = '❌ পুনরুদ্ধার ব্যর্থ: $e');
    } finally {
      if (mounted) setState(() => _dbRestoreBusy = false);
    }
  }

  /// Phase 7: `দাখিলা_টাইপ.ext` নামের একাধিক ফাইল একসাথে ইমপোর্ট।
  Future<void> _bulkImport() async {
    final provider = context.read<StudentProvider>();
    final List<PlatformFile> files;
    try {
      files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
      );
    } catch (e) {
      debugPrint('Pick error: $e');
      return;
    }
    final paths = files.map((f) => f.path).whereType<String>().toList();
    if (paths.isEmpty || !mounted) return;
    setState(() => _importing = true);
    try {
      final res = await provider.bulkImportDocuments(paths);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Bulk ইমপোর্ট: ${res.assigned} টি সফল, ${res.skipped} টি স্কিপ '
                '(নাম ফরম্যাট বা দাখিলা মেলেনি)')),
      );
    } catch (e) {
      debugPrint('Bulk import failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bulk ইমপোর্ট ব্যর্থ')),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  /// প্রতিষ্ঠানের লোগো বাছাই → branding ফোল্ডারে কপি → প্রোভাইডারে সেভ।
  Future<void> _pickLogo() async {
    final provider = context.read<StudentProvider>();
    List<PlatformFile> files;
    try {
      files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg'],
      );
    } catch (e) {
      debugPrint('Pick logo error: $e');
      return;
    }
    final path = files.isEmpty ? null : files.single.path;
    if (path == null || !mounted) return;
    setState(() => _logoBusy = true);
    try {
      final saved = await StorageService.saveLogo(path);
      if (!mounted) return;
      if (saved != null) {
        await provider.setInstitutionLogo(saved);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('লোগো সেভ হয়েছে ✓')),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('লোগো সেভ ব্যর্থ')),
        );
      }
    } finally {
      if (mounted) setState(() => _logoBusy = false);
    }
  }

  /// ফোল্ডার থেকে এক ধরনের ডকুমেন্ট বাল্ক-ইমপোর্ট (নাম = দাখিলা নম্বর)।
  Future<void> _importFolder(DocType type) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${type.label} ফোল্ডার ইমপোর্ট'),
        content: Text('ফোল্ডারের সব ফাইল ${type.label} হিসেবে ইমপোর্ট হবে।\n'
            'প্রতিটি ফাইলের নাম দাখিলা নম্বর হতে হবে (যেমন 281.jpg)।'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('বাতিল'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('ফোল্ডার বাছুন'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final provider = context.read<StudentProvider>();
    setState(() {
      _folderBusy = true;
      _folderCancel = false;
      _folderStatus = 'ফোল্ডার কপি হচ্ছে...';
    });
    try {
      final res = await provider.importFolderDocuments(
        type,
        onProgress: (done, total) {
          if (mounted) {
            setState(() => _folderStatus = 'ইমপোর্ট হচ্ছে... $done/$total');
          }
        },
        shouldStop: () => _folderCancel,
      );
      if (!mounted) return;
      setState(() {
        _folderStatus = res.cancelled
            ? 'বাতিল — ${res.assigned} টি ইমপোর্ট হয়েছিল'
            : (res.total == 0
                ? 'ফোল্ডারে কোনো ফাইল পাওয়া যায়নি (সাব-ফোল্ডার নয়, ফাইলের ফোল্ডার বাছুন)'
                : 'শেষ — ${res.assigned} সফল, ${res.skipped} স্কিপ (মোট ${res.total})');
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                '${type.label}: ${res.assigned} টি ইমপোর্ট, ${res.skipped} টি স্কিপ')),
      );
    } catch (e) {
      debugPrint('Folder import failed: $e');
      if (mounted) setState(() => _folderStatus = 'ব্যর্থ: $e');
    } finally {
      if (mounted) setState(() => _folderBusy = false);
    }
  }

  Future<void> _confirmReset() async {
    final provider = context.read<StudentProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ডাটা রিসেট করবেন?'),
        content: const Text(
            'সব রেকর্ড মুছে অ্যাপের বান্ডেল করা ডেটা আবার লোড হবে। '
            'তোলা ছবির ফাইল ডিস্কে থেকে যাবে, তবে রেকর্ডের সংযোগ মুছে যাবে।'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('বাতিল'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('রিসেট', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await provider.resetData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ডাটা রিসেট সম্পন্ন')),
      );
    }
  }

  /// Phase 6: পুরনো flat ছবিগুলো v2 ফোল্ডার-লেআউটে সাজানো।
  Future<void> _migrateStorage() async {
    final provider = context.read<StudentProvider>();
    setState(() {
      _migrating = true;
      _migrateStatus = 'স্ক্যান হচ্ছে...';
    });
    try {
      final moved = await provider.migrateStorageToV2(
        onProgress: (done, total) {
          if (mounted) {
            setState(() => _migrateStatus = 'সাজানো হচ্ছে... $done/$total');
          }
        },
      );
      if (!mounted) return;
      setState(() => _migrateStatus = 'শেষ — $moved টি ছবি নতুন ফোল্ডারে');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$moved টি ছবি v2 ফোল্ডারে সাজানো হয়েছে ✓')),
      );
    } catch (e) {
      debugPrint('Migrate failed: $e');
      if (mounted) setState(() => _migrateStatus = 'ব্যর্থ — আবার চেষ্টা করুন');
    } finally {
      if (mounted) setState(() => _migrating = false);
    }
  }

  /// Fresh install-এর পর গ্যালারি থেকে পুরনো তোলা ছবি ফিরিয়ে আনে।
  Future<void> _recover() async {
    final provider = context.read<StudentProvider>();
    setState(() {
      _recovering = true;
      _recoverStatus = 'স্ক্যান হচ্ছে...';
    });
    try {
      final restored = await provider.recoverFromGallery(
        onProgress: (done, total) {
          if (mounted) {
            setState(() => _recoverStatus = 'ফেরানো হচ্ছে... $done/$total');
          }
        },
      );
      if (!mounted) return;
      setState(() => _recoverStatus = 'শেষ — $restored টি ছবি ফিরে এসেছে');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$restored টি ছবি রিকভারি হয়েছে ✓')),
      );
    } on PlatformException catch (e) {
      debugPrint('Recover failed: ${e.code} ${e.message}');
      if (mounted) {
        setState(() => _recoverStatus = e.code == 'PERMISSION_DENIED'
            ? 'স্টোরেজ অনুমতি দিন, তারপর আবার চাপুন'
            : 'ব্যর্থ: ${e.message}');
      }
    } catch (e) {
      debugPrint('Recover failed: $e');
      if (mounted) setState(() => _recoverStatus = 'ব্যর্থ — আবার চেষ্টা করুন');
    } finally {
      if (mounted) setState(() => _recovering = false);
    }
  }

  /// Phase 4: পুরনো সব তোলা ছবি গ্যালারিতে ব্যাকআপ (best-effort, idempotent)।
  Future<void> _backupAll() async {
    final provider = context.read<StudentProvider>();
    setState(() {
      _backingUp = true;
      _backupStatus = 'শুরু হচ্ছে...';
    });
    try {
      final ok = await provider.backupAllToGallery(
        onProgress: (done, total) {
          if (mounted) setState(() => _backupStatus = 'চলছে... $done/$total');
        },
      );
      if (!mounted) return;
      setState(() => _backupStatus = 'শেষ — $ok টি ছবি ব্যাকআপ হয়েছে');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$ok টি ছবি গ্যালারিতে ব্যাকআপ হয়েছে ✓')),
      );
    } catch (e) {
      debugPrint('Backup all failed: $e');
      if (mounted) setState(() => _backupStatus = 'ব্যর্থ — আবার চেষ্টা করুন');
    } finally {
      if (mounted) setState(() => _backingUp = false);
    }
  }

  /// DocumentsUI (সিস্টেম ফাইল ম্যানেজার) দিয়ে আউটপুট ফোল্ডার খোলার চেষ্টা।
  Future<void> _openFolder() async {
    if (_folderPath.isEmpty) return;
    final storagePath =
        _folderPath.replaceFirst('/storage/emulated/0/', 'primary:');
    try {
      final intent = AndroidIntent(
        action: 'android.intent.action.VIEW',
        data:
            'content://com.android.externalstorage.documents/document/$storagePath',
        type: '*/*',
        flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
      );
      await intent.launch();
    } catch (e) {
      debugPrint('Open folder failed: $e');
      await _copyPath(); // ব্যর্থ হলে অন্তত পাথ কপি হবে
    }
  }

  Future<void> _copyPath() async {
    await Clipboard.setData(ClipboardData(text: _folderPath));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ফোল্ডারের পাথ কপি হয়েছে')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('সেটিংস'),
        backgroundColor: Colors.teal,
      ),
      body: Consumer<StudentProvider>(
        builder: (context, provider, _) {
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(children: [
                        Icon(Icons.backup, color: Colors.red),
                        SizedBox(width: 8),
                        Text('ব্যাকআপ ও পুনরুদ্ধার (সম্পূর্ণ)',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                      ]),
                      const SizedBox(height: 6),
                      const Text(
                        'ডেটাবেস + সব ছবি/ডকুমেন্ট (v2 ফোল্ডার) + লোগো — '
                        'এক ZIP-এ। আনইনস্টল, ফোন-বদল বা ক্লিয়ার-ডেটার '
                        'আগে অবশ্যই নিন।',
                        style: TextStyle(fontSize: 11, color: Colors.black54),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _dbBackupBusy ? null : _fullBackup,
                              icon: _dbBackupBusy
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : const Icon(Icons.download),
                              label: const Text('ব্যাকআপ তৈরি'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed: _dbRestoreBusy ? null : _fullRestore,
                              icon: _dbRestoreBusy
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : const Icon(Icons.restore),
                              label: const Text('পুনরুদ্ধার'),
                            ),
                          ),
                        ],
                      ),
                      if (_dbBackupMsg.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(_dbBackupMsg,
                            style: const TextStyle(fontSize: 12)),
                      ],
                      if (_dbRestoreMsg.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(_dbRestoreMsg,
                            style: const TextStyle(fontSize: 12)),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(children: [
                        Icon(Icons.business, color: Colors.teal),
                        SizedBox(width: 8),
                        Text('প্রতিষ্ঠান (কাস্টমাইজ)',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                      ]),
                      const SizedBox(height: 8),
                      TextFormField(
                        initialValue: provider.institutionName,
                        decoration: const InputDecoration(
                            labelText: 'প্রতিষ্ঠানের নাম',
                            border: OutlineInputBorder(),
                            isDense: true),
                        onChanged: provider.setInstitutionName,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.black26),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: (provider.institutionLogoPath != null &&
                                    File(provider.institutionLogoPath!)
                                        .existsSync())
                                ? Image.file(
                                    File(provider.institutionLogoPath!),
                                    fit: BoxFit.contain)
                                : const Icon(Icons.image,
                                    color: Colors.black26),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _logoBusy ? null : _pickLogo,
                              icon: _logoBusy
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : const Icon(Icons.upload),
                              label: const Text('লোগো বাছুন'),
                            ),
                          ),
                          if (provider.institutionLogoPath != null)
                            IconButton(
                              tooltip: 'লোগো মুছুন',
                              icon: const Icon(Icons.delete_outline,
                                  color: Colors.red),
                              onPressed: _logoBusy
                                  ? null
                                  : () => provider.setInstitutionLogo(null),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'নাম ও লোগো অ্যাপ হেডার ও রিপোর্ট ফরমে দেখা যাবে',
                        style: TextStyle(fontSize: 11, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(children: [
                        Icon(Icons.folder_copy, color: Colors.deepPurple),
                        SizedBox(width: 8),
                        Text('ফোল্ডার থেকে ডকুমেন্ট ইমপোর্ট',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                      ]),
                      const SizedBox(height: 6),
                      const Text(
                        'ফাইলের নাম দাখিলা নম্বর হতে হবে (যেমন 281.jpg)। '
                        'ফোল্ডারের সব ফাইল একটা একটা করে সঠিক ছাত্রের স্লটে বসবে। '
                        'তিন ধরনের জন্য তিনবার ফোল্ডার বাছুন।',
                        style: TextStyle(fontSize: 11, color: Colors.black54),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _folderBusy
                            ? null
                            : () => _importFolder(DocType.PHOTO),
                        icon: const Icon(Icons.photo_camera),
                        label: const Text('ছবি ফোল্ডার ইমপোর্ট'),
                      ),
                      const SizedBox(height: 6),
                      OutlinedButton.icon(
                        onPressed: _folderBusy
                            ? null
                            : () => _importFolder(DocType.BIRTH),
                        icon: const Icon(Icons.description),
                        label: const Text('জন্মসনদ ফোল্ডার ইমপোর্ট'),
                      ),
                      const SizedBox(height: 6),
                      OutlinedButton.icon(
                        onPressed: _folderBusy
                            ? null
                            : () => _importFolder(DocType.FORM),
                        icon: const Icon(Icons.upload_file),
                        label: const Text('ফরম ফোল্ডার ইমপোর্ট'),
                      ),
                      if (_folderStatus.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(_folderStatus,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.black87)),
                      ],
                      if (_folderBusy) ...[
                        const SizedBox(height: 6),
                        const LinearProgressIndicator(),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () => _folderCancel = true,
                            child: const Text('বাতিল করুন'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('থিম',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      SegmentedButton<ThemeMode>(
                        segments: const [
                          ButtonSegment(
                              value: ThemeMode.system, label: Text('সিস্টেম')),
                          ButtonSegment(
                              value: ThemeMode.light, label: Text('লাইট')),
                          ButtonSegment(
                              value: ThemeMode.dark, label: Text('ডার্ক')),
                        ],
                        selected: {provider.themeMode},
                        onSelectionChanged: (s) =>
                            provider.setThemeMode(s.first),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('পাসপোর্ট ছবির রং',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Auto-enhancement'),
                        subtitle: const Text(
                            'মূল ছবি অপরিবর্তিত রেখে final JPEG-এ প্রয়োগ হবে'),
                        value: provider.isAutoEnhancementEnabled,
                        onChanged: provider.setAutoEnhancementEnabled,
                      ),
                      SegmentedButton<PassportPreset>(
                        segments: PassportPreset.values
                            .map((p) =>
                                ButtonSegment(value: p, label: Text(p.label)))
                            .toList(),
                        selected: {provider.passportPreset},
                        onSelectionChanged: provider.isAutoEnhancementEnabled
                            ? (value) => provider.setPassportPreset(value.first)
                            : null,
                      ),
                      const SizedBox(height: 10),
                      const Text('ডকুমেন্ট স্ক্যান — ডিফল্ট ফিল্টার',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      SegmentedButton<DocumentFilterMode>(
                        segments: const [
                          ButtonSegment(
                              value: DocumentFilterMode.original,
                              label: Text('Original')),
                          ButtonSegment(
                              value: DocumentFilterMode.magic,
                              label: Text('Magic')),
                          ButtonSegment(
                              value: DocumentFilterMode.gray,
                              label: Text('Gray')),
                          ButtonSegment(
                              value: DocumentFilterMode.bw, label: Text('B&W')),
                        ],
                        selected: {provider.defaultDocFilter},
                        onSelectionChanged: (s) =>
                            provider.setDefaultDocFilter(s.first),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.school, color: Colors.teal),
                      title: const Text('শিক্ষক তালিকা সম্পাদনা'),
                      subtitle: const Text(
                          'রিপোর্ট ফরমে দায়িত্বপ্রাপ্ত শিক্ষকের নাম ও মোবাইল — '
                          'যোগ/সম্পাদনা/মুছে ফেলা করা যায়'),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const TeacherManageScreen()),
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.lock_outline,
                          color: Colors.deepOrange),
                      title: const Text('কেস নোট PIN'),
                      subtitle: const Text(
                          'কেস নোট (রিপোর্ট ফরম) খোলার সময় পিন চাওয়া হবে — '
                          'সেট/পরিবর্তন/সরানো করুন'),
                      onTap: () => CaseNotesGuard.manageFromSettings(context),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: _importing
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.upload_file, color: Colors.teal),
                      title: const Text('JSON ফাইল থেকে ডাটা ইমপোর্ট'),
                      subtitle: const Text(
                          'ডিভাইস থেকে JSON ফাইল বেছে নিন। নতুন ডেটা পুরনোটার বদলে '
                          'বসবে — তোলা ছবি ও অ্যাপে সম্পাদিত রেকর্ডের তথ্য সংরক্ষিত থাকবে।'),
                      onTap: _importing ? null : _importJson,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.table_view, color: Colors.teal),
                      title: const Text('Excel ফাইল থেকে ডাটা ইমপোর্ট (.xlsx)'),
                      subtitle: const Text(
                          'কলাম হেডার (যেকোনো ক্রমে): DAKHILA, STU_NAME, CLASS_NAME, '
                          'FORIK_NO, FATHER_NAME, DAKHILA_YEAR। অ্যাপে সম্পাদিত '
                          'রেকর্ডের তথ্য সংরক্ষিত থাকবে।'),
                      onTap: _importing ? null : _importExcel,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.published_with_changes,
                          color: Colors.deepOrange),
                      title: const Text(
                          'Excel রাউন্ড-ট্রিপ আপডেট (En/Ar নাম ইত্যাদি)'),
                      subtitle: const Text(
                          'এক্সপোর্ট করা xlsx (Excel-এ পূর্ণ তথ্য) সম্পাদনা করে '
                          'ফেরত দিন — শুধু ভরা সেল কার্যকর হবে; দাখিলা মিলিয়ে '
                          'আপডেট হয় (নাম×৩-লিপি, পিতা-মাতা, মোবাইল, নম্বর, জন্ম-তথ্য)।'),
                      onTap: _importing ? null : _importRoundTrip,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.drive_folder_upload,
                          color: Colors.teal),
                      title: const Text('Bulk ইমপোর্ট (ফাইলনাম থেকে)'),
                      subtitle: const Text(
                          'একসাথে অনেক ফাইল বাছুন — নাম হতে হবে '
                          'দাখিলা_টাইপ.ext (যেমন 281_BIRTH.pdf, 282_FORM.jpg)'),
                      onTap: _importing ? null : _bulkImport,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: _backingUp
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.backup, color: Colors.teal),
                      title: const Text('সব ডকুমেন্ট গ্যালারিতে ব্যাকআপ'),
                      subtitle: Text(_backupStatus.isEmpty
                          ? 'PHOTO, জন্মনিবন্ধন ও image ফরম গ্যালারির '
                              'Pictures/DakhilaCamera-তে কপি হবে '
                              '(uninstall করলেও থাকবে)'
                          : _backupStatus),
                      onTap: _backingUp ? null : _backupAll,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: _migrating
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.drive_file_move,
                              color: Colors.deepPurple),
                      title: const Text('স্টোরেজ সাজান (v2 ফোল্ডার)'),
                      subtitle: Text(_migrateStatus.isEmpty
                          ? 'পুরনো flat ছবিগুলো ছাত্র-প্রতি ফোল্ডারে গুছিয়ে দেবে '
                              '(ক্লাস/ফরিক/দাখিলা)'
                          : _migrateStatus),
                      onTap:
                          (_migrating || _backingUp) ? null : _migrateStorage,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: _recovering
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.restore, color: Colors.indigo),
                      title: const Text('পুরনো ছবি রিকভারি (গ্যালারি থেকে)'),
                      subtitle: Text(_recoverStatus.isEmpty
                          ? 'Fresh install/আপডেটের পর গ্যালারির কপি থেকে তোলা ছবি '
                              'ফিরিয়ে আনে — দাখিলা নম্বর মিলিয়ে'
                          : _recoverStatus),
                      onTap: (_recovering || _backingUp) ? null : _recover,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.restart_alt, color: Colors.red),
                      title: const Text('ডাটা রিসেট'),
                      subtitle: const Text(
                          'সব রেকর্ড মুছে অ্যাপের বান্ডেল করা ডেটা আবার লোড হবে'),
                      onTap: _importing ? null : _confirmReset,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(children: [
                        Icon(Icons.folder_open, color: Colors.teal),
                        SizedBox(width: 8),
                        Text('আউটপুট ফোল্ডার',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                      ]),
                      const SizedBox(height: 8),
                      SelectableText(
                        _folderPath.isEmpty ? '...' : _folderPath,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black87),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _openFolder,
                              icon: const Icon(Icons.folder_open),
                              label: const Text('ফোল্ডার খুলুন'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _copyPath,
                              icon: const Icon(Icons.copy),
                              label: const Text('পাথ কপি'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'প্রতিটি ছবি গ্যালারির Pictures/DakhilaCamera ফোল্ডারেও সেভ হয়।\n'
                        'টিপ: কিছু ফোনে File Manager "Android/data" ফোল্ডার দেখায় না — '
                        'তখন "পাথ কপি" করে ফাইল ম্যানেজারের অ্যাড্রেস বারে বসান।',
                        style: TextStyle(fontSize: 11, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
