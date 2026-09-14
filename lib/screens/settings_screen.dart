import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../providers/student_provider.dart';

/// সেটিংস: কাস্টম JSON ইমপোর্ট, ডেটা রিসেট, আউটপুট ফোল্ডার।
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _importing = false;
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

  Future<void> _importJson() async {
    final provider = context.read<StudentProvider>();
    final List<PlatformFile> files;
    try {
      files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
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
      final imported = await provider.importFromJsonFile(path);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$imported টি রেকর্ড ইমপোর্ট হয়েছে ✓')),
      );
    } catch (e) {
      debugPrint('Import error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'ইমপোর্ট ব্যর্থ — ফাইলটি সঠিক ফরম্যাটের JSON কি না যাচাই করুন')),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
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
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Column(
              children: [
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
                      'বসবে — একই দাখিলার তোলা ছবির হিসাব থেকে যাবে।'),
                  onTap: _importing ? null : _importJson,
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
                    style: const TextStyle(fontSize: 12, color: Colors.black87),
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
                    'টিপ: কিছু ফোনে File Manager "Android/data" ফোল্ডার দেখায় না — '
                    'তখন "পাথ কপি" করে ফাইল ম্যানেজারের অ্যাড্রেস বারে বসান।',
                    style: TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
