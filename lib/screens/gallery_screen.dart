import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/document.dart';
import '../providers/student_provider.dart';
import 'image_viewer_screen.dart';

/// Phase 5A/8: তোলা ছবির গ্যালারি গ্রিড — missing-type ফিল্টার সহ।
/// মূল লিস্টের বর্তমান ফিল্টার (ক্লাস/ফরিক) মেনে চলে।
class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  DocType? _missingFilter; // null = সব

  Widget _chip(DocType? value, String label) {
    final selected = _missingFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        selected: selected,
        label: Text(label),
        onSelected: (_) => setState(() => _missingFilter = value),
      ),
    );
  }

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
          final shown = _missingFilter == null
              ? captured
              : captured
                  .where((s) => !provider.withDocs(s).hasDoc(_missingFilter!))
                  .toList();
          return Column(
            children: [
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.all(8),
                  children: [
                    _chip(null, 'সব'),
                    _chip(DocType.BIRTH, 'জন্মসনদ বাকি'),
                    _chip(DocType.FORM, 'ফরম বাকি'),
                  ],
                ),
              ),
              Expanded(
                child: shown.isEmpty
                    ? const Center(
                        child: Text('এই ফিল্টারে কোনো ছবি নেই'),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(8),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 6,
                          crossAxisSpacing: 6,
                          childAspectRatio: 0.72,
                        ),
                        itemCount: shown.length,
                        itemBuilder: (context, i) {
                          final s = shown[i];
                          final missingLabel = _missingFilter?.label;
                          return InkWell(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      ImageViewerScreen(student: s)),
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
                                      cacheWidth: 300,
                                      errorBuilder: (_, __, ___) =>
                                          const ColoredBox(
                                        color: Colors.grey,
                                        child: Icon(Icons.broken_image,
                                            color: Colors.white),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  s.dakhila,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (_missingFilter != null &&
                                    missingLabel != null)
                                  Text(
                                    '$missingLabel বাকি',
                                    style: const TextStyle(
                                        fontSize: 10, color: Colors.red),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
