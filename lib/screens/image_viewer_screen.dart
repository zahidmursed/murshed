import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/student.dart';
import '../providers/student_provider.dart';
import 'camera_screen.dart';

/// তোলা ছবি full-screen দেখা + zoom, retake ও delete।
class ImageViewerScreen extends StatelessWidget {
  final Student student;

  const ImageViewerScreen({super.key, required this.student});

  Future<void> _confirmDelete(BuildContext context) async {
    final provider = context.read<StudentProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${student.dakhila}.jpg মুছে ফেলবেন?'),
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
    if (confirmed == true && context.mounted) {
      final trashPath = await provider.clearCaptured(student.dakhila);
      if (!context.mounted) return;
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
                  provider.restoreFromTrash(student.dakhila, trashPath),
            ),
          ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('${student.dakhila} — ${student.stuName}'),
        backgroundColor: Colors.teal,
        actions: [
          IconButton(
            tooltip: 'আবার তুলুন',
            icon: const Icon(Icons.replay),
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                    builder: (_) => CameraScreen(student: student)),
              );
            },
          ),
          IconButton(
            tooltip: 'মুছে ফেলুন',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDelete(context),
          ),
        ],
      ),
      body: InteractiveViewer(
        maxScale: 4,
        child: Center(
          child: student.imagePath != null
              ? Image.file(File(student.imagePath!), fit: BoxFit.contain)
              : const Icon(Icons.broken_image, color: Colors.white54, size: 64),
        ),
      ),
    );
  }
}
