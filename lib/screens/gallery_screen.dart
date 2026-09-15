import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/document.dart';
import '../models/student.dart';
import '../providers/student_provider.dart';
import '../utils/gallery_saver.dart';
import 'image_viewer_screen.dart';

/// PHOTO, BIRTH ও FORM — তিন ধরনের সেভ করা ডকুমেন্টের গ্যালারি।
class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  DocType? _typeFilter; // null = সব

  // পারফরম্যান্স ফিক্স: build-এর ভিতরে প্রতি ডকে existsSync() না চালিয়ে
  // ডেটা বদলালে একবার async-ভাবে হিসাব হয় (হাজার খানেক ফাইলে jank কমায়)।
  List<(Student, StudentDocument)> _entries = const [];
  List<Student>? _lastSource;
  int _lastSignature = -1;
  int _computeId = 0;
  int _lastDoneId = 0;

  bool get _computingEntries => _computeId != _lastDoneId;

  Widget _chip(DocType? value, String label) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: FilterChip(
          selected: _typeFilter == value,
          label: Text(label),
          onSelected: (_) => setState(() => _typeFilter = value),
        ),
      );

  /// পারফরম্যান্স ফিক্স: ডেটা বদলালে (load/capture/delete) একবার async-ভাবে
  /// হিসাব হয় — build-এ আর কোনো synchronous file I/O থাকে না। ডেটা-সিগনেচার
  /// (লিস্ট আইডেন্টিটি + মোট ডক সংখ্যা) বদলালে নতুন হিসাব, নাহলে ক্যাশ।
  void _refreshEntries(StudentProvider provider) {
    final source = provider.students;
    var signature = source.length * 31;
    for (final s in source) {
      signature += provider.docCountOf(s.dakhila);
    }
    if (identical(_lastSource, source) && signature == _lastSignature) return;
    _lastSource = source;
    _lastSignature = signature;
    final id = ++_computeId;
    unawaited(() async {
      final entries = <(Student, StudentDocument)>[];
      for (final student in source) {
        for (final type in DocType.values) {
          final doc = provider.docOf(student.dakhila, type);
          if (doc != null && await File(doc.filePath).exists()) {
            entries.add((student, doc));
          }
        }
      }
      if (!mounted || id != _computeId) return; // পুরনো হিসাব — নতুনটা আসছে
      setState(() {
        _entries = entries;
        _lastDoneId = id;
      });
    }());
  }

  Future<void> _open(Student student, StudentDocument doc) async {
    if (doc.type == DocType.PHOTO) {
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ImageViewerScreen(student: student)),
      );
      return;
    }
    await GallerySaver.viewFile(
        path: doc.filePath, mime: doc.mimeTypeForView);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.teal,
        title: const Text('ডকুমেন্ট গ্যালারি'),
      ),
      body: Consumer<StudentProvider>(
        builder: (context, provider, _) {
          _refreshEntries(provider);
          final entries = _entries;
          final shown = _typeFilter == null
              ? entries
              : entries.where((entry) => entry.$2.type == _typeFilter).toList();
          return Column(
            children: [
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.all(8),
                  children: [
                    _chip(null, 'সব (${entries.length})'),
                    _chip(DocType.PHOTO, 'ছবি'),
                    _chip(DocType.BIRTH, 'জন্মনিবন্ধন'),
                    _chip(DocType.FORM, 'ফরম'),
                  ],
                ),
              ),
              Expanded(
                child: (_computingEntries && _entries.isEmpty)
                    ? const Center(child: CircularProgressIndicator())
                    : shown.isEmpty
                        ? const Center(
                            child: Text('এই ধরনের কোনো ডকুমেন্ট নেই'))
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
                          final (student, doc) = shown[i];
                          final isPdf = doc.ext.toLowerCase() == 'pdf';
                          return InkWell(
                            onTap: () => _open(student, doc),
                            child: Column(children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: isPdf
                                      ? const ColoredBox(
                                          color: Color(0xfff5e3e0),
                                          child: Center(
                                            child: Icon(Icons.picture_as_pdf,
                                                color: Colors.deepOrange,
                                                size: 44),
                                          ),
                                        )
                                      : Image.file(File(doc.filePath),
                                          fit: BoxFit.cover,
                                          width: double.infinity,
                                          cacheWidth: 300,
                                          errorBuilder: (_, __, ___) =>
                                              const ColoredBox(
                                                color: Colors.grey,
                                                child: Icon(Icons.broken_image,
                                                    color: Colors.white),
                                              )),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(student.dakhila,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold)),
                              Text(doc.type.label,
                                  style: const TextStyle(
                                      fontSize: 10, color: Colors.teal)),
                            ]),
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
