import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/document.dart';
import '../models/student.dart';
import '../providers/student_provider.dart';
import '../services/export_service.dart';
import '../utils/gallery_saver.dart';
import 'camera_screen.dart';
import 'image_viewer_screen.dart';
import 'student_report_screen.dart';

/// Phase 7: ছাত্রের ৩টি ডকুমেন্টের ড্যাশবোর্ড (PHOTO/BIRTH/FORM)।
class DocumentDashboardScreen extends StatefulWidget {
  final Student student;
  const DocumentDashboardScreen({super.key, required this.student});

  @override
  State<DocumentDashboardScreen> createState() =>
      _DocumentDashboardScreenState();
}

class _DocumentDashboardScreenState extends State<DocumentDashboardScreen> {
  bool _busy = false;

  Future<void> _pickDocument(DocType type) async {
    final provider = context.read<StudentProvider>();
    final List<PlatformFile> files;
    try {
      files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: type.allowedExtensions,
      );
    } catch (e) {
      debugPrint('Pick error: $e');
      return;
    }
    final path = files.isEmpty ? null : files.first.path;
    if (path == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await provider.assignDocument(
        dakhila: widget.student.dakhila,
        type: type,
        srcPath: path,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${type.label} সেভ হয়েছে ✓')),
      );
    } catch (e) {
      debugPrint('Assign failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('সেভ ব্যর্থ: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeDocument(DocType type) async {
    final provider = context.read<StudentProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${type.label} মুছে ফেলবেন?'),
        content: const Text('ফাইল ও রেকর্ড দুটোই মুছে যাবে।'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('বাতিল'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('মুছুন', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      // কনসিসটেন্সি ফিক্স: PHOTO মোছাও এখন undo-যোগ্য — viewer/review-এর
      // মতোই ট্র্যাশে যায় ও ৫ সেকেন্ড পুনরুদ্ধার পাওয়া যায়। BIRTH/FORM
      // আগের মতোই সরাসরি মুছে যায়।
      String? trashPath;
      if (type == DocType.PHOTO) {
        trashPath = await provider.clearCaptured(widget.student.dakhila);
      } else {
        await provider.removeDocument(
            dakhila: widget.student.dakhila, type: type);
      }
      if (!mounted) return;
      if (trashPath != null) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: const Text('ছবি মুছে ফেলা হয়েছে'),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'পুনরুদ্ধার',
              onPressed: () => provider
                  .restoreFromTrash(widget.student.dakhila, trashPath!),
            ),
          ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('মুছে ফেলা হয়েছে')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _viewDoc(StudentDocument doc) async {
    await GallerySaver.viewFile(
        path: doc.filePath, mime: doc.mimeTypeForView);
  }

  /// Phase 8: ছাত্রের সব ডক এক merged PDF-এ → শেয়ার শিট।
  Future<void> _exportMergedPdf() async {
    setState(() => _busy = true);
    try {
      final path = await ExportService.exportStudentMergedPdf(
          dakhila: widget.student.dakhila);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Merged PDF সেভ হয়েছে')),
      );
      await GallerySaver.shareFile(path: path, mime: 'application/pdf');
    } catch (e) {
      debugPrint('Merged PDF failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ব্যর্থ: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.student.dakhila} — ${widget.student.stuName}'),
        backgroundColor: Colors.teal,
      ),
      body: Consumer<StudentProvider>(
        builder: (context, provider, _) {
          final withDocs = provider.withDocs(widget.student);
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _headerCard(withDocs),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => StudentReportScreen(
                                    student: widget.student)),
                          ),
                  icon: const Icon(Icons.assignment),
                  label: const Text('রিপোর্ট ফরম দেখুন'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _exportMergedPdf,
                  icon: const Icon(Icons.merge_type),
                  label: const Text('Merged PDF (এক ফাইলে সব ডক)'),
                ),
              ),
              const SizedBox(height: 12),
              _docCard(context, withDocs, DocType.PHOTO),
              const SizedBox(height: 12),
              _docCard(context, withDocs, DocType.BIRTH),
              const SizedBox(height: 12),
              _docCard(context, withDocs, DocType.FORM),
            ],
          );
        },
      ),
    );
  }

  Widget _headerCard(StudentWithDocs withDocs) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 64,
                  height: 64,
                  child: CircularProgressIndicator(
                    value: withDocs.progress,
                    strokeWidth: 6,
                    backgroundColor: Colors.grey.shade300,
                    color: Colors.teal,
                  ),
                ),
                Text(
                  '${withDocs.completedCount}/3',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.student.stuName,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  Text(
                      '${widget.student.className} | ফরিক ${widget.student.forikNo}',
                      style: const TextStyle(color: Colors.black54)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _docCard(
      BuildContext context, StudentWithDocs withDocs, DocType type) {
    final StudentDocument? doc = withDocs.docs[type];
    final bool fileExists = doc != null && File(doc.filePath).existsSync();
    final isPdf = doc?.ext == 'pdf';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  type == DocType.PHOTO
                      ? Icons.photo_camera
                      : (isPdf ? Icons.picture_as_pdf : Icons.image),
                  color: doc != null ? Colors.teal : Colors.grey,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('${type.label} (${type.name})',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                _statusChip(doc != null),
              ],
            ),
            const SizedBox(height: 8),
            if (doc == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('— এখনো যোগ করা হয়নি',
                    style: TextStyle(color: Colors.black45)),
              )
            else ...[
              if (!isPdf)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(doc.filePath),
                    height: 140,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    cacheWidth: 500,
                    errorBuilder: (_, __, ___) => const ColoredBox(
                        color: Colors.grey, child: Icon(Icons.broken_image)),
                  ),
                )
              else
                Row(children: [
                  Icon(isPdf ? Icons.picture_as_pdf : Icons.image,
                      size: 40, color: Colors.deepOrange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(doc.filePath,
                        style: const TextStyle(fontSize: 11),
                        overflow: TextOverflow.ellipsis),
                  ),
                ]),
              if (doc.updatedAt != null && doc.updatedAt!.length >= 10) ...[
                const SizedBox(height: 6),
                Text('আপডেট: ${doc.updatedAt!.substring(0, 10)}',
                    style:
                        const TextStyle(fontSize: 11, color: Colors.black54)),
              ],
              const SizedBox(height: 8),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _actions(context, type, doc, fileExists),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _actions(
      BuildContext context, DocType type, StudentDocument? doc, bool exists) {
    final actions = <Widget>[];
    if (type == DocType.PHOTO) {
      actions.add(_btn(Icons.photo_camera, 'ক্যামেরা', () {
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => CameraScreen(student: widget.student)));
      }));
      // ফিক্স: PHOTO-তেও ফাইল বাছুন — স্টুডিও/প্রস্তুত ছবি সরাসরি বসানো যায়
      actions.add(
          _btn(Icons.upload_file, 'ফাইল বাছুন', () => _pickDocument(type)));
    } else {
      // BIRTH/FORM: ক্যামেরা দিয়েও তোলা যায় (পুরো পেজ, ক্রপ ছাড়া)
      actions.add(_btn(Icons.photo_camera, 'ক্যামেরা', () {
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) =>
                    CameraScreen(student: widget.student, docType: type)));
      }));
      actions.add(
          _btn(Icons.upload_file, 'ফাইল বাছুন', () => _pickDocument(type)));
    }
    if (exists && doc != null) {
      if (type == DocType.PHOTO) {
        actions.add(_btn(Icons.visibility, 'দেখুন', () {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => ImageViewerScreen(student: widget.student)));
        }));
      } else {
        actions.add(_btn(Icons.visibility, 'দেখুন', () => _viewDoc(doc)));
      }
      actions.add(_btn(
          Icons.delete_outline, 'মুছুন', () => _removeDocument(type),
          color: Colors.red));
    }
    return actions;
  }

  Widget _btn(IconData icon, String label, VoidCallback onTap,
      {Color color = Colors.teal}) {
    return OutlinedButton.icon(
      onPressed: _busy ? null : onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.5)),
      ),
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }

  Widget _statusChip(bool exists) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: exists ? Colors.green.shade100 : Colors.grey.shade300,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        exists ? 'সম্পন্ন ✓' : 'বাকি',
        style: TextStyle(
            fontSize: 11,
            color: exists ? Colors.green.shade800 : Colors.black54),
      ),
    );
  }
}
