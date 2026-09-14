import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/student_provider.dart';
import '../services/export_service.dart';
import '../utils/gallery_saver.dart';

/// Phase 5A: অফিস এক্সপোর্ট — ZIP, Missing CSV, PDF প্রিন্ট শিট।
/// স্কোপ = মূল লিস্টের বর্তমান ফিল্টার (ক্লাস/ফরিক)।
class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key});

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  String? _busy; // 'zip' | 'csv' | 'pdf'
  String _progressText = '';

  void _onProgress(int done, int total) {
    if (mounted) setState(() => _progressText = 'চলছে... $done/$total');
  }

  Future<void> _run(String kind) async {
    final provider = context.read<StudentProvider>();
    final classFilter =
        provider.selectedClass.isEmpty ? null : provider.selectedClass;
    final forikFilter =
        provider.selectedForik.isEmpty ? null : provider.selectedForik;
    setState(() {
      _busy = kind;
      _progressText = 'শুরু হচ্ছে...';
    });
    try {
      final String path;
      if (kind == 'zip') {
        path = await ExportService.exportZip(
          classFilter: classFilter,
          forikFilter: forikFilter,
          onProgress: _onProgress,
        );
      } else if (kind == 'csv') {
        path = await ExportService.exportMissingCsv(
          classFilter: classFilter,
          forikFilter: forikFilter,
        );
      } else {
        path = await ExportService.exportPdfSheet(
          classFilter: classFilter,
          forikFilter: forikFilter,
          onProgress: _onProgress,
        );
      }
      if (!mounted) return;
      setState(() {
        _busy = null;
        _progressText = '';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('সেভ হয়েছে: $path')),
      );
      final mime = kind == 'zip'
          ? 'application/zip'
          : kind == 'csv'
              ? 'text/csv'
              : 'application/pdf';
      await GallerySaver.shareFile(path: path, mime: mime);
    } on StateError catch (e) {
      if (!mounted) return;
      setState(() => _busy = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      debugPrint('Export failed: $e');
      if (!mounted) return;
      setState(() => _busy = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('এক্সপোর্ট ব্যর্থ: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('এক্সপোর্ট'),
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
                      const Text('স্কোপ',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(provider.selectedClass.isEmpty &&
                              provider.selectedForik.isEmpty
                          ? 'সব ডেটা (কোনো ফিল্টার নেই)'
                          : '${provider.selectedClass.isEmpty ? 'সব ক্লাস' : provider.selectedClass} > '
                              '${provider.selectedForik.isEmpty ? 'সব ফরিক' : 'ফরিক ${provider.selectedForik}'}'),
                      const SizedBox(height: 4),
                      Text(
                        'মোট ${provider.total} • তোলা ${provider.captured} • বাকি ${provider.remaining}',
                        style: const TextStyle(color: Colors.black54),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'টিপ: মূল লিস্টে ক্লাস/ফরিক ফিল্টার করে এলে সেটাই স্কোপ হবে',
                        style: TextStyle(fontSize: 11, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _tile(
                icon: Icons.folder_zip,
                color: Colors.teal,
                title: 'ZIP এক্সপোর্ট (তোলা ছবি)',
                subtitle:
                    'ফোল্ডার স্ট্রাকচার: ক্লাস/ফরিক/দাখিলা.jpg + ভিতরে missing report',
                busy: _busy == 'zip',
                progress: _busy == 'zip' ? _progressText : '',
                onTap: _busy != null ? null : () => _run('zip'),
              ),
              _tile(
                icon: Icons.description,
                color: Colors.deepOrange,
                title: 'Missing Report (CSV)',
                subtitle: 'যাদের ছবি এখনো তোলা হয়নি — Excel-এ খোলা যায়',
                busy: _busy == 'csv',
                progress: _busy == 'csv' ? _progressText : '',
                onTap: _busy != null ? null : () => _run('csv'),
              ),
              _tile(
                icon: Icons.print,
                color: Colors.indigo,
                title: 'PDF প্রিন্ট শিট',
                subtitle: 'A4 পেজে ৯টি করে পাসপোর্ট ছবি + দাখিলা নম্বর',
                busy: _busy == 'pdf',
                progress: _busy == 'pdf' ? _progressText : '',
                onTap: _busy != null ? null : () => _run('pdf'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _tile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required bool busy,
    required String progress,
    required VoidCallback? onTap,
  }) {
    return Card(
      child: ListTile(
        leading: busy
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(icon, color: color),
        title: Text(title),
        subtitle: Text(busy && progress.isNotEmpty ? progress : subtitle),
        onTap: onTap,
      ),
    );
  }
}
