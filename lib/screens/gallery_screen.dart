import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/student_provider.dart';
import 'image_viewer_screen.dart';

/// Phase 5A: শুধু তোলা ছবির গ্যালারি গ্রিড — দ্রুত ভেরিফিকেশন।
/// মূল লিস্টের বর্তমান ফিল্টার (ক্লাস/ফরিক) মেনে চলে।
class GalleryScreen extends StatelessWidget {
  const GalleryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.teal,
        title: Consumer<StudentProvider>(
          builder: (_, p, __) => Text('তোলা ছবি (${p.captured})'),
        ),
      ),
      body: Consumer<StudentProvider>(
        builder: (context, provider, _) {
          final captured = provider.students
              .where((s) => s.isCaptured == 1 && s.imagePath != null)
              .toList();
          if (captured.isEmpty) {
            return const Center(
              child: Text('এই স্কোপে এখনো কোনো ছবি তোলা হয়নি'),
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              childAspectRatio: 0.72,
            ),
            itemCount: captured.length,
            itemBuilder: (context, i) {
              final s = captured[i];
              return InkWell(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => ImageViewerScreen(student: s)),
                ),
                child: Column(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(s.imagePath!),
                          fit: BoxFit.cover,
                          width: double.infinity,
                          cacheWidth: 300, // thumbnail — মেমোরি বাঁচাতে
                          errorBuilder: (_, __, ___) => const ColoredBox(
                            color: Colors.grey,
                            child:
                                Icon(Icons.broken_image, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      s.dakhila,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
