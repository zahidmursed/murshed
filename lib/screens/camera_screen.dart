import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../models/student.dart';
import '../providers/student_provider.dart';
import '../utils/image_processor.dart';

class CameraScreen extends StatefulWidget {
  final Student student;
  const CameraScreen({super.key, required this.student});
  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _init = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _setupCamera();
  }

  Future<void> _setupCamera() async {
    setState(() {
      _error = null;
      _init = false;
    });
    await _controller?.dispose();
    _controller = null;
    try {
      _cameras = await availableCameras();
      if (!mounted) return;
      if (_cameras == null || _cameras!.isEmpty) {
        setState(() => _error = 'কোনো ক্যামেরা পাওয়া যায়নি');
        return;
      }
      final controller = CameraController(
        _cameras![0],
        ResolutionPreset.high,
        enableAudio: false,
      );
      _controller = controller;
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _init = true);
    } catch (e) {
      debugPrint('Camera init error: $e');
      if (mounted) {
        setState(() => _error = _friendlyCameraError(e));
      }
    }
  }

  /// init/permission error-কে ব্যবহারবান্ধব বাংলা মেসেজে রূপান্তর করে।
  String _friendlyCameraError(Object e) {
    final String s = e.toString().toLowerCase();
    if (s.contains('cameraaccessdenied') ||
        s.contains('access denied') ||
        s.contains('permission')) {
      return 'ক্যামেরার অনুমতি দেওয়া হয়নি। '
          'সিস্টেম সেটিংস থেকে এই অ্যাপের CAMERA permission চালু করুন।';
    }
    if (s.contains('in use') ||
        s.contains('busy') ||
        s.contains('disconnected')) {
      return 'ক্যামেরা এখন ব্যবহার করা যাচ্ছে না। আবার চেষ্টা করুন।';
    }
    return 'ক্যামেরা চালু করা যায়নি। আবার চেষ্টা করুন।';
  }

  /// External storage পাওয়া না গেলে app documents directory ব্যবহার করবে।
  Future<Directory> _getSaveDirectory() async {
    final appDir = await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    final saveDir = Directory('${appDir.path}/DakhilaCamera');
    if (!await saveDir.exists()) await saveDir.create(recursive: true);
    return saveDir;
  }

  Future<void> _takePicture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _saving) {
      return;
    }
    // await-এর আগেই capture — context যেন async gap-এ ব্যবহার না হয়
    final provider = Provider.of<StudentProvider>(context, listen: false);
    setState(() => _saving = true);
    try {
      final XFile file = await controller.takePicture();
      if (!mounted) return;

      final saveDir = await _getSaveDirectory();
      if (!mounted) return;
      final savePath = '${saveDir.path}/${widget.student.dakhila}.jpg';

      if (provider.isPassportMode) {
        // Passport size: 600×800 (3:4) — isolate-এ center crop + resize
        final bytes = await File(file.path).readAsBytes();
        final processed = await processPassportInIsolate(bytes);
        if (processed != null) {
          await File(savePath).writeAsBytes(processed);
        } else {
          await File(file.path).copy(savePath);
        }
      } else {
        // Original mode — যেমন তোলা তেমন সেভ
        await File(file.path).copy(savePath);
      }

      await DatabaseHelper.instance
          .updateImage(widget.student.dakhila, savePath);
      if (!mounted) return;

      provider.markCaptured(widget.student.dakhila, savePath);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${widget.student.dakhila}.jpg সেভ হয়েছে ✓')),
      );
      if (provider.isSerialMode) {
        final next = provider.getNext(widget.student.dakhila);
        if (next != null) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => CameraScreen(student: next)),
          );
        } else {
          Navigator.pop(context);
        }
      } else {
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('CameraScreen Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ত্রুটি: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  /// init/permission ব্যর্থ হলে ব্যবহারবান্ধব error দৃশ্য + retry বাটন।
  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 56),
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _setupCamera,
              icon: const Icon(Icons.refresh),
              label: const Text('আবার চেষ্টা করুন'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
            'দাখিলা: ${widget.student.dakhila} — ${widget.student.stuName}'),
        backgroundColor: Colors.teal,
      ),
      body: _error != null
          ? _buildErrorView()
          : _init
              ? Stack(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: double.infinity,
                      child: CameraPreview(_controller!),
                    ),
                    Positioned(
                      top: 16,
                      left: 16,
                      right: 16,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        color: Colors.black54,
                        child: Column(
                          children: [
                            Text(
                              '${widget.student.stuName} | ${widget.student.className} | ফরিক ${widget.student.forikNo}',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 16),
                              textAlign: TextAlign.center,
                            ),
                            Consumer<StudentProvider>(
                              builder: (_, p, __) => Text(
                                p.isPassportMode
                                    ? 'পাসপোর্ট সাইজ (600×800)'
                                    : 'অরিজিনাল সাইজ',
                                style:
                                    const TextStyle(color: Colors.yellowAccent),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 30,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: _saving
                            ? const CircularProgressIndicator()
                            : FloatingActionButton.large(
                                backgroundColor: Colors.white,
                                onPressed: _takePicture,
                                child: const Icon(Icons.camera_alt,
                                    size: 40, color: Colors.black),
                              ),
                      ),
                    ),
                  ],
                )
              : const Center(child: CircularProgressIndicator()),
    );
  }
}
