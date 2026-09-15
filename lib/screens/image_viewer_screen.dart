import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:provider/provider.dart';

import '../models/document.dart';
import '../models/student.dart';
import '../providers/student_provider.dart';
import '../utils/gallery_saver.dart';
import '../utils/image_processor.dart';
import 'camera_screen.dart';

/// তোলা ছবি full-screen দেখা + zoom + retake/delete — এবং নিচে
/// সম্পাদনা টুলবার (মুক্ত ক্রপ / পাসপোর্ট ক্রপ / রিসাইজ)।
class ImageViewerScreen extends StatefulWidget {
  final Student student;

  const ImageViewerScreen({super.key, required this.student});

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  bool _busy = false;
  int _version = 0;

  String? get _path => widget.student.imagePath;

  /// একই ফাইলে নতুন JPEG লেখে + DB/মেমোরি/গ্যালারি সিঙ্ক + প্রদর্শন রিফ্রেশ।
  Future<void> _applyEditedBytes(List<int> out) async {
    final path = _path;
    if (path == null) return;
    final provider = context.read<StudentProvider>();
    await File(path).writeAsBytes(out, flush: true);
    await provider.markCaptured(widget.student.dakhila, path);
    await provider.markDocumentSaved(
        widget.student.dakhila, DocType.PHOTO, path);
    await GallerySaver.saveToGallery(
        filePath: path, fileName: '${widget.student.dakhila}.jpg');
    // ImageCache পুরনো ডিকোড ধরে রাখে — evict না করলে পুরনো ছবিই দেখাত।
    await FileImage(File(path)).evict();
    if (!mounted) return;
    setState(() => _version++);
  }

  Future<void> _crop({required bool passport}) async {
    final path = _path;
    if (path == null || _busy) return;
    final provider = context.read<StudentProvider>();
    CroppedFile? crop;
    try {
      crop = await ImageCropper().cropImage(
        sourcePath: path,
        aspectRatio: passport
            ? CropAspectRatio(
                ratioX: passportWidth.toDouble(),
                ratioY: passportHeight.toDouble())
            : null,
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 100,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: passport ? 'পাসপোর্ট ক্রপ' : 'মুক্ত ক্রপ',
            toolbarColor: Colors.teal,
            toolbarWidgetColor: Colors.white,
            lockAspectRatio: passport,
            hideBottomControls: false,
          )
        ],
      );
    } catch (e) {
      debugPrint('Crop editor failed: $e');
    }
    if (crop == null || !mounted) return;
    setState(() => _busy = true);
    try {
      List<int> out;
      if (passport) {
        final processed = await processPassportInIsolate(
          await crop.readAsBytes(),
          provider.passportPreset,
          provider.isAutoEnhancementEnabled,
        );
        if (processed == null) throw StateError('invalid crop');
        out = processed;
      } else {
        out = await crop.readAsBytes();
      }
      if (!mounted) return;
      await _applyEditedBytes(out);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ছবি সম্পাদনা হয়েছে ✓')),
      );
    } catch (e) {
      debugPrint('Apply crop failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('সম্পাদনা করা যায়নি')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resize() async {
    final path = _path;
    if (path == null || _busy) return;
    final provider = context.read<StudentProvider>();
    final choice = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('রিসাইজ'),
        content: const Text('ছবিটি কোন মাপে নেবেন?\n(একই ফাইলে সেভ হবে)'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('বাতিল'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 431),
            child: const Text('পাসপোর্ট 431×531'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 800),
            child: const Text('ছোট — সর্বোচ্চ 800px'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 1200),
            child: const Text('মাঝারি — সর্বোচ্চ 1200px'),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final bytes = await File(path).readAsBytes();
      List<int>? out;
      if (choice == 431) {
        // পাসপোর্ট মাপ: 431:531 center-crop → ঠিক 431×531 (enhance সেটিং মেনে)
        out = await processPassportInIsolate(
            bytes, provider.passportPreset, provider.isAutoEnhancementEnabled);
      } else {
        out = await resizeImageInIsolate(bytes, maxSide: choice);
      }
      if (out == null) throw StateError('resize failed');
      if (!mounted) return;
      await _applyEditedBytes(out);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ছবি রিসাইজ হয়েছে ✓')),
      );
    } catch (e) {
      debugPrint('Resize failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('রিসাইজ করা যায়নি')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmDelete() async {
    final provider = context.read<StudentProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${widget.student.dakhila}.jpg মুছে ফেলবেন?'),
        content: const Text(
            'ছবির ফাইল ডিলিট হবে এবং রেকর্ড আবার "বাকি" হিসেবে চিহ্নিত হবে।'),
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
    if (confirmed == true && mounted) {
      final trashPath = await provider.clearCaptured(widget.student.dakhila);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      if (trashPath != null) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: const Text('ছবি মুছে ফেলা হয়েছে'),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'পুনরুদ্ধার',
              onPressed: () =>
                  provider.restoreFromTrash(widget.student.dakhila, trashPath),
            ),
          ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final path = _path;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('${widget.student.dakhila} — ${widget.student.stuName}'),
        backgroundColor: Colors.teal,
        actions: [
          IconButton(
            tooltip: 'আবার তুলুন',
            icon: const Icon(Icons.replay),
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                    builder: (_) => CameraScreen(student: widget.student)),
              );
            },
          ),
          IconButton(
            tooltip: 'মুছে ফেলুন',
            icon: const Icon(Icons.delete_outline),
            onPressed: _busy ? null : _confirmDelete,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: InteractiveViewer(
              maxScale: 4,
              child: Center(
                child: path != null
                    ? Image.file(File(path),
                        key: ValueKey(_version), fit: BoxFit.contain)
                    : const Icon(Icons.broken_image,
                        color: Colors.white54, size: 64),
              ),
            ),
          ),
          _editBar(),
        ],
      ),
    );
  }

  Widget _editBar() {
    final hasPhoto = _path != null;
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        color: Colors.black54,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: _busy
            ? const Center(
                child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white)),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _editAction(Icons.crop_free, 'ক্রপ',
                      hasPhoto ? () => _crop(passport: false) : null),
                  _editAction(Icons.crop, 'পাসপোর্ট',
                      hasPhoto ? () => _crop(passport: true) : null),
                  _editAction(
                      Icons.photo_size_select_large, 'রিসাইজ',
                      hasPhoto ? _resize : null),
                ],
              ),
      ),
    );
  }

  Widget _editAction(IconData icon, String label, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(height: 4),
            Text(label,
                style: const TextStyle(color: Colors.white, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}