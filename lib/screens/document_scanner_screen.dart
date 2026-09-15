import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../models/document.dart';
import '../models/student.dart';
import '../providers/student_provider.dart';
import '../services/scanner_service.dart';
import '../services/storage_service.dart';
import '../utils/gallery_saver.dart';
import '../utils/image_processor.dart';
import 'camera_screen.dart';

/// BIRTH/FORM ডকুমেন্ট স্ক্যানার — ML Kit দিয়ে তুলে (অটো এজ-ডিটেকশন +
/// বাঁকা সোজা + ছায়ামুক্ত), পেজ জোড়া → ফিল্টার বাছাই → সঠিক স্লটে সেভ।
class DocumentScannerScreen extends StatefulWidget {
  final Student student;
  final DocType type;

  const DocumentScannerScreen({
    super.key,
    required this.student,
    required this.type,
  });

  @override
  State<DocumentScannerScreen> createState() => _DocumentScannerScreenState();
}

class _DocumentScannerScreenState extends State<DocumentScannerScreen> {
  bool _scanning = true; // ML Kit UI চালু আছে
  bool _processing = false; // পেজ প্রস্তুত/ফিল্টার তৈরি হচ্ছে
  bool _saving = false;
  String? _error;
  bool _fallbackToCamera = false;
  int _pageCount = 0;
  Uint8List? _merged;
  DocumentFilterMode _mode = DocumentFilterMode.magic;
  final Map<DocumentFilterMode, Uint8List> _previews = {};
  bool _compare = false;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  Future<void> _startScan() async {
    setState(() {
      _scanning = true;
      _error = null;
    });
    try {
      final paths = await ScannerService.scanDocument(pageLimit: 5);
      if (!mounted) return;
      if (paths.isEmpty) {
        Navigator.pop(context); // ইউজার বাতিল
        return;
      }
      setState(() {
        _scanning = false;
        _processing = true;
        _pageCount = paths.length;
      });
      // পেজগুলো লম্বা বাহু 1600px-এ সীমিত — ফাইল ছোট ও প্রসেস দ্রুত
      final pages = <Uint8List>[];
      for (final path in paths) {
        final bytes = await File(path).readAsBytes();
        final limited = await limitLongSideInIsolate(bytes, maxSide: 1600);
        pages.add(limited ?? bytes);
      }
      final merged = await mergePagesVerticallyInIsolate(pages);
      if (merged == null) throw StateError('empty scan');
      _merged = merged;
      _previews.clear();
      if (!mounted) return;
      // ডিফল্ট ফিল্টার = সেটিংসে বাছাই করা মোড
      _mode = context.read<StudentProvider>().defaultDocFilter;
      setState(() => _processing = false);
      await _buildPreviews();
    } on ScannerException catch (e) {
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _processing = false;
        _error = e.message;
        _fallbackToCamera = e.fallbackToCamera;
      });
    } catch (e) {
      debugPrint('Scan failed: $e');
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _processing = false;
        _error = 'স্ক্যান ব্যর্থ হয়েছে';
        _fallbackToCamera = true;
      });
    }
  }

  /// ৪টি ফিল্টার মোডের প্রিভিউ তৈরি করে (পরপর, isolate-এ)।
  Future<void> _buildPreviews() async {
    final merged = _merged;
    if (merged == null) return;
    setState(() => _processing = true);
    for (final mode in DocumentFilterMode.values) {
      if (mode == DocumentFilterMode.original) {
        _previews[mode] = merged;
      } else {
        final out = await enhanceDocumentInIsolate(merged, mode);
        if (!mounted) return;
        if (out != null) _previews[mode] = out;
        setState(() {});
      }
    }
    if (!mounted) return;
    setState(() => _processing = false);
  }

  Future<void> _save() async {
    final merged = _merged;
    if (merged == null || _saving) return;
    final provider = context.read<StudentProvider>();
    setState(() => _saving = true);
    try {
      final filtered = _mode == DocumentFilterMode.original
          ? merged
          : (await enhanceDocumentInIsolate(merged, _mode)) ?? merged;
      final dir = await getTemporaryDirectory();
      final stage = Directory('${dir.path}/DakhilaCamera/doc_scan');
      if (!await stage.exists()) await stage.create(recursive: true);
      final tempFile =
          '${stage.path}/${widget.student.dakhila}_${widget.type.name}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(tempFile).writeAsBytes(filtered, flush: true);
      await provider.assignDocument(
        dakhila: widget.student.dakhila,
        type: widget.type,
        srcPath: tempFile,
      );
      // ক্যামেরা-ফ্লোর মতো গ্যালারি সিঙ্ক (v2 পাথ নিজেই হিসাব করি)
      final v2Path = await StorageService.documentPath(
        widget.student.className,
        widget.student.forikNo,
        widget.student.dakhila,
        widget.type,
        'jpg',
      );
      await GallerySaver.saveToGallery(
        filePath: v2Path,
        fileName: '${widget.student.dakhila}_${widget.type.name}.jpg',
      );
      try {
        final f = File(tempFile);
        if (await f.exists()) await f.delete();
      } catch (_) {}
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(content: Text('${widget.type.label} স্ক্যান সেভ হয়েছে ✓')),
      );
    } catch (e) {
      debugPrint('Scan save failed: $e');
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('সেভ ব্যর্থ: $e')),
      );
    }
  }

  /// ML Kit-এর কর্নার ভুল হলে ম্যানুয়ালি ঠিক করা — বিদ্যমান uCrop এডিটরে
  /// মুক্ত ক্রপ; কাটা ফল নতুন base হয় ও সব ফিল্টার-প্রিভিউ নতুন করে তৈরি হয়।
  Future<void> _fixCorners() async {
    final base = _merged;
    if (base == null || _processing || _saving) return;
    setState(() => _processing = true);
    CroppedFile? crop;
    try {
      final tempSource =
          await StorageService.temporaryCropSource(widget.student.dakhila);
      await File(tempSource).writeAsBytes(base, flush: true);
      crop = await ImageCropper().cropImage(
        sourcePath: tempSource,
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 95,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'কর্নার ঠিক করুন',
            toolbarColor: Colors.teal,
            toolbarWidgetColor: Colors.white,
            lockAspectRatio: false,
            hideBottomControls: false,
          )
        ],
      );
      final f = File(tempSource);
      if (await f.exists()) await f.delete();
    } catch (e) {
      debugPrint('Fix corners failed: $e');
    }
    if (!mounted) return;
    if (crop == null) {
      // ইউজার বাতিল করেছে
      setState(() => _processing = false);
      return;
    }
    try {
      final bytes = await crop.readAsBytes();
      _merged = bytes;
      _previews.clear();
    } catch (e) {
      debugPrint('Read cropped result failed: $e');
    }
    if (!mounted) return;
    await _buildPreviews();
  }

  String _modeLabel(DocumentFilterMode mode) => switch (mode) {
        DocumentFilterMode.original => 'Original — যেমন স্ক্যান হয়েছে',
        DocumentFilterMode.magic => 'Magic — সাদা ব্যাকগ্রাউন্ড, গাঢ় লেখা',
        DocumentFilterMode.gray => 'Gray — সাদাকালো, ছোট ফাইল',
        DocumentFilterMode.bw => 'B&W — ফটোকপি স্টাইল',
      };

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_scanning) {
      body = const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.teal),
            SizedBox(height: 16),
            Text('স্ক্যানার খুলছে...', style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    } else if (_error != null) {
      body = _errorView();
    } else if (_processing || _merged == null) {
      body = Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Colors.teal),
            const SizedBox(height: 16),
            Text(
              _pageCount == 0 ? 'প্রস্তুত হচ্ছে...' : '$_pageCount পেজ প্রসেস হচ্ছে...',
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      );
    } else {
      body = _resultView();
    }
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('${widget.type.label} স্ক্যান: ${widget.student.dakhila}'),
        backgroundColor: Colors.teal,
      ),
      body: body,
    );
  }

  Widget _resultView() {
    final preview = _previews[_mode];
    return Column(
      children: [
        Container(
          width: double.infinity,
          color: Colors.black87,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: _processing || _saving
                    ? null
                    : () => setState(() => _compare = !_compare),
                icon: Icon(
                    _compare ? Icons.view_agenda : Icons.grid_view,
                    color: Colors.white70,
                    size: 18),
                label: Text(_compare ? 'একটি দেখুন' : 'তুলনা করুন',
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 12)),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _processing || _saving ? null : _fixCorners,
                icon: const Icon(Icons.crop, color: Colors.white70, size: 18),
                label: const Text('কর্নার ঠিক করুন',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
              ),
            ],
          ),
        ),
        Expanded(
          child: _compare
              ? _compareView()
              : InteractiveViewer(
                  maxScale: 4,
                  child: Center(
                    child: preview == null
                        ? const CircularProgressIndicator(color: Colors.teal)
                        : Image.memory(preview, fit: BoxFit.contain),
                  ),
                ),
        ),
        Container(
          width: double.infinity,
          color: Colors.black87,
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 64,
                  child: Row(
                    children: [
                      for (final mode in DocumentFilterMode.values)
                        Expanded(
                          child: GestureDetector(
                            onTap: _saving
                                ? null
                                : () => setState(() => _mode = mode),
                            child: Container(
                              margin:
                                  const EdgeInsets.symmetric(horizontal: 3),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: _mode == mode
                                      ? Colors.tealAccent
                                      : Colors.white24,
                                  width: _mode == mode ? 2 : 1,
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              padding: const EdgeInsets.all(2),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: _previews[mode] != null
                                    ? Image.memory(_previews[mode]!,
                                        fit: BoxFit.cover)
                                    : const ColoredBox(color: Colors.grey),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(_modeLabel(_mode),
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save),
                    label: Text(_saving ? 'সেভ হচ্ছে...' : '✅ সেভ করুন'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _compareView() {
    return GridView.count(
      crossAxisCount: 2,
      padding: const EdgeInsets.all(6),
      childAspectRatio: 0.75,
      children: [
        for (final mode in DocumentFilterMode.values)
          GestureDetector(
            onTap: _saving
                ? null
                : () => setState(() {
                      _mode = mode;
                      _compare = false;
                    }),
            child: Container(
              margin: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                border: Border.all(
                  color: _mode == mode ? Colors.tealAccent : Colors.white24,
                  width: _mode == mode ? 2 : 1,
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: _previews[mode] != null
                          ? Image.memory(_previews[mode]!, fit: BoxFit.contain)
                          : const ColoredBox(color: Colors.grey),
                    ),
                    Positioned(
                      left: 4,
                      bottom: 4,
                      child: Container(
                        color: Colors.black54,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        child: Text(mode.name,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 11)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 56),
            const SizedBox(height: 16),
            Text(_error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 16)),
            const SizedBox(height: 24),
            if (_fallbackToCamera)
              FilledButton.icon(
                onPressed: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                      builder: (_) => CameraScreen(
                          student: widget.student, docType: widget.type)),
                ),
                icon: const Icon(Icons.photo_camera),
                label: const Text('ক্যামেরা দিয়ে তুলুন'),
              ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ফিরে যান',
                  style: TextStyle(color: Colors.white70)),
            ),
          ],
        ),
      ),
    );
  }
}