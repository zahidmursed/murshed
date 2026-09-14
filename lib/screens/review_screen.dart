import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/student.dart';
import '../providers/student_provider.dart';
import 'camera_screen.dart';

/// ছবি সেভ হওয়ার পর রিভিউ — ভুল ছবি হলে আবার তোলা যায়,
/// serial mode-এ সরাসরি পরের দাখিলায় যাওয়া যায়।
class ReviewScreen extends StatelessWidget {
  final Student student;
  final String imagePath;
  final Student? next;

  const ReviewScreen({
    super.key,
    required this.student,
    required this.imagePath,
    this.next,
  });

  void _retake(BuildContext context) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => CameraScreen(student: student)),
    );
  }

  void _advance(BuildContext context) {
    if (next != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => CameraScreen(student: next!)),
      );
    } else {
      Navigator.pop(context);
    }
  }

  /// ছবি ডিলিট (ফাইল + রেকর্ড) — এরপর একই শিক্ষার্থীর জন্য ক্যামেরায় ফিরে যায়।
  Future<void> _confirmDelete(BuildContext context) async {
    final provider = context.read<StudentProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${student.dakhila}.jpg মুছে ফেলবেন?'),
        content: const Text(
            'ছবির ফাইল ডিলিট হবে; এরপর আবার তোলার জন্য ক্যামেরায় ফিরে যান।'),
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
    if (confirmed != true || !context.mounted) return;
    final trashPath = await provider.clearCaptured(student.dakhila);
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => CameraScreen(student: student)),
    );
    if (trashPath != null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: const Text('ছবি মুছে ফেলা হয়েছে'),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'পুনরুদ্ধার',
            onPressed: () =>
                provider.restoreFromTrash(student.dakhila, trashPath),
          ),
        ));
    }
  }

  Widget _roundAction(IconData icon, String tooltip, VoidCallback onTap,
      {Color color = Colors.white}) {
    return Tooltip(
      message: tooltip,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          shape: const CircleBorder(),
          padding: const EdgeInsets.all(16),
          side: const BorderSide(color: Colors.white54),
        ),
        child: Icon(icon, color: color),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('রিভিউ: ${student.dakhila} — ${student.stuName}'),
        backgroundColor: Colors.teal,
      ),
      body: Column(
        children: [
          Expanded(
            child: InteractiveViewer(
              maxScale: 4,
              child: Center(
                child: Image.file(File(imagePath), fit: BoxFit.contain),
              ),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: Colors.black54,
            child: Text(
              '✓ ${student.dakhila}.jpg সেভ হয়েছে | ${student.className} | '
              'ফরিক ${student.forikNo}',
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _roundAction(Icons.replay, 'আবার তুলুন', () => _retake(context)),
              const SizedBox(width: 10),
              _roundAction(
                Icons.delete_outline,
                'মুছুন',
                () => _confirmDelete(context),
                color: Colors.redAccent,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _advance(context),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.teal,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: Icon(next != null ? Icons.skip_next : Icons.check),
                  label:
                      Text(next != null ? 'পরের: ${next!.dakhila}' : 'ঠিক আছে'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
