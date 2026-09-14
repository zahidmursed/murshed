import 'dart:io';

import 'package:flutter/material.dart';

import '../models/student.dart';
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
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _retake(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: const Icon(Icons.replay),
                  label: const Text('আবার তুলুন'),
                ),
              ),
              const SizedBox(width: 12),
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
