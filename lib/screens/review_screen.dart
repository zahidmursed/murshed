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

/// Review keeps the raw capture temporarily, so each manual crop starts clean.
class ReviewScreen extends StatefulWidget {
  final Student student;
  final String imagePath;
  final String? originalCapturePath;
  final int qualityFlags;
  final Student? next;
  const ReviewScreen(
      {super.key,
      required this.student,
      required this.imagePath,
      this.originalCapturePath,
      this.qualityFlags = 0,
      this.next});
  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  bool _applying = false;
  int _version = 0;

  Future<void> _removeRaw() async {
    final path = widget.originalCapturePath;
    if (path == null) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  Future<void> _retake() async {
    await _removeRaw();
    if (!mounted) return;
    Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (_) => CameraScreen(student: widget.student)));
  }

  Future<void> _advance() async {
    await _removeRaw();
    if (!mounted) return;
    if (widget.next == null) {
      Navigator.pop(context);
    } else {
      Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (_) => CameraScreen(student: widget.next!)));
    }
  }

  /// The native editor supplies drag, pinch-to-zoom, and Reset. The fixed ratio
  /// guarantees that apply always produces the app's 431×531 JPEG.
  Future<void> _crop() async {
    final raw = widget.originalCapturePath;
    if (raw == null || !await File(raw).exists()) return;
    final crop = await ImageCropper().cropImage(
      sourcePath: raw,
      aspectRatio: CropAspectRatio(
        ratioX: passportWidth.toDouble(),
        ratioY: passportHeight.toDouble(),
      ),
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 100,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'পাসপোর্ট ক্রপ',
          toolbarColor: Colors.teal,
          toolbarWidgetColor: Colors.white,
          lockAspectRatio: true,
          hideBottomControls: false,
        )
      ],
    );
    if (crop == null || !mounted) return;
    setState(() => _applying = true);
    try {
      final provider = context.read<StudentProvider>();
      final out = await processPassportInIsolate(
        await crop.readAsBytes(),
        provider.passportPreset,
        provider.isAutoEnhancementEnabled,
      );
      if (out == null) throw StateError('invalid crop');
      await File(widget.imagePath).writeAsBytes(out, flush: true);
      // ImageCache পুরনো ডিকোড ধরে রাখে — evict না করলে ক্রপের পরেও
      // পুরনো ছবিই দেখাতে পারে।
      await FileImage(File(widget.imagePath)).evict();
      await provider.markCaptured(widget.student.dakhila, widget.imagePath);
      // ফিক্স: ক্রপের পরে documents.updated_at-ও নতুন হয় — ড্যাশবোর্ডে
      // সঠিক "আপডেট" তারিখ দেখায়।
      await provider.markDocumentSaved(
          widget.student.dakhila, DocType.PHOTO, widget.imagePath);
      await GallerySaver.saveToGallery(
          filePath: widget.imagePath,
          fileName: '${widget.student.dakhila}.jpg');
      if (mounted) {
        setState(() => _version++);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ক্রপ প্রয়োগ করা হয়েছে ✓')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ক্রপ প্রয়োগ করা যায়নি')));
      }
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  Future<void> _delete() async {
    final provider = context.read<StudentProvider>();
    final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
              title: Text('${widget.student.dakhila}.jpg মুছে ফেলবেন?'),
              content: const Text('ছবির ফাইল ডিলিট হবে; এরপর আবার তোলা যাবে।'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(d, false),
                    child: const Text('বাতিল')),
                TextButton(
                    onPressed: () => Navigator.pop(d, true),
                    child: const Text('মুছুন',
                        style: TextStyle(color: Colors.red)))
              ],
            ));
    if (ok != true || !mounted) return;
    final trash = await provider.clearCaptured(widget.student.dakhila);
    await _removeRaw();
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (_) => CameraScreen(student: widget.student)));
    if (trash != null) {
      messenger.showSnackBar(SnackBar(
          content: const Text('ছবি মুছে ফেলা হয়েছে'),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
              label: 'পুনরুদ্ধার',
              onPressed: () =>
                  provider.restoreFromTrash(widget.student.dakhila, trash))));
    }
  }

  Widget _action(IconData icon, String tip, VoidCallback? tap,
          {Color color = Colors.white}) =>
      Tooltip(
          message: tip,
          child: OutlinedButton(
              onPressed: tap,
              style: OutlinedButton.styleFrom(
                  shape: const CircleBorder(),
                  padding: const EdgeInsets.all(14),
                  side: const BorderSide(color: Colors.white54)),
              child: Icon(icon, color: color)));

  @override
  Widget build(BuildContext context) {
    final warnings = <String>[
      if (widget.qualityFlags & 1 != 0) 'আলো কম',
      if (widget.qualityFlags & 2 != 0) 'ছবি ঝাপসা হতে পারে'
    ];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
          title: Text(
              'রিভিউ: ${widget.student.dakhila} — ${widget.student.stuName}'),
          backgroundColor: Colors.teal),
      body: Column(children: [
        if (warnings.isNotEmpty)
          Container(
              width: double.infinity,
              color: Colors.orange.shade800,
              padding: const EdgeInsets.all(10),
              child: Text(
                  'সতর্কতা: ${warnings.join(' ও ')}। প্রয়োজন হলে আবার তুলুন।',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white))),
        Expanded(
            child: InteractiveViewer(
                maxScale: 4,
                child: Center(
                    child: Image.file(File(widget.imagePath),
                        key: ValueKey(_version), fit: BoxFit.contain)))),
        Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: Colors.black54,
            child: Text(
                '✓ ${widget.student.dakhila}.jpg সেভ হয়েছে | ${widget.student.className} | ফরিক ${widget.student.forikNo}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70))),
      ]),
      bottomNavigationBar: SafeArea(
          child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                _action(Icons.replay, 'আবার তুলুন', _applying ? null : _retake),
                const SizedBox(width: 4),
                _action(
                    Icons.crop,
                    'ম্যানুয়াল ক্রপ',
                    _applying || widget.originalCapturePath == null
                        ? null
                        : _crop,
                    color: Colors.lightBlueAccent),
                const SizedBox(width: 4),
                _action(
                    Icons.delete_outline, 'মুছুন', _applying ? null : _delete,
                    color: Colors.redAccent),
                const SizedBox(width: 8),
                Expanded(
                    child: FilledButton.icon(
                        onPressed: _applying ? null : _advance,
                        style: FilledButton.styleFrom(
                            backgroundColor: Colors.teal,
                            padding: const EdgeInsets.symmetric(vertical: 12)),
                        icon: _applying
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : Icon(widget.next == null
                                ? Icons.check
                                : Icons.skip_next),
                        label: Text(widget.next == null
                            ? 'ঠিক আছে'
                            : 'পরের: ${widget.next!.dakhila}'))),
              ]))),
    );
  }
}
