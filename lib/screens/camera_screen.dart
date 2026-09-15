import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../models/document.dart';
import '../models/student.dart';
import '../providers/student_provider.dart';
import '../services/storage_service.dart';
import '../utils/gallery_saver.dart';
import '../utils/image_processor.dart';
import 'review_screen.dart';

class CameraScreen extends StatefulWidget {
  final Student student;

  /// PHOTO = পাসপোর্ট ক্রপ সহ; BIRTH/FORM = ডকুমেন্ট মোড (পুরো পেজ, ক্রপ ছাড়া)
  final DocType docType;
  const CameraScreen({
    super.key,
    required this.student,
    this.docType = DocType.PHOTO,
  });
  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _init = false;
  bool _saving = false;
  bool _readyToCapture = false;
  bool _switching = false;
  bool _isTorchOn = false;
  int _cameraIndex = 0;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  double _baseZoom = 1.0;
  double _currentZoom = 1.0;
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
      _readyToCapture = false;
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
      await _initController(_cameraIndex.clamp(0, _cameras!.length - 1));
    } catch (e) {
      debugPrint('Camera init error: $e');
      if (mounted) {
        setState(() => _error = _friendlyCameraError(e));
      }
    }
  }

  Future<void> _initController(int index) async {
    final controller = CameraController(
      _cameras![index],
      ResolutionPreset.high,
      enableAudio: false,
    );
    _cameraIndex = index;
    _controller = controller;
    _currentZoom = 1.0;
    _baseZoom = 1.0;
    await controller.initialize();
    if (!mounted) {
      await controller.dispose();
      return;
    }
    // zoom সীমা ক্যাশ করা (camera 0.10.x-এ CameraValue-তে zoom ফিল্ড নেই;
    // সাপোর্ট না থাকলে দুটোই 1.0 — তখন pinch কিছু করবে না)
    try {
      _minZoom = await controller.getMinZoomLevel();
      _maxZoom = await controller.getMaxZoomLevel();
    } catch (_) {
      _minZoom = 1.0;
      _maxZoom = 1.0;
    }
    // নতুন ক্যামেরা/লেন্সে AF ও AE auto mode-এ ফিরিয়ে সামান্য settle time দিই।
    // সব ফোনে status API নেই, তাই এটি conservative 450ms guard।
    try {
      await controller.setFocusMode(FocusMode.auto);
      await controller.setExposureMode(ExposureMode.auto);
    } catch (_) {
      // কিছু front camera এই controls expose করে না।
    }
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() => _init = true);
    Future.delayed(const Duration(milliseconds: 450), () {
      if (mounted && identical(_controller, controller)) {
        setState(() => _readyToCapture = true);
      }
    });
  }

  /// pinch-to-zoom — scale অনুযায়ী zoom level বাড়ায়/কমায়।
  Future<void> _onZoomUpdate(ScaleUpdateDetails details) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (_maxZoom <= _minZoom) return; // zoom সাপোর্ট নেই
    final double target =
        (_baseZoom * details.scale).clamp(_minZoom, _maxZoom).toDouble();
    if ((target - _currentZoom).abs() < 0.01) return;
    _currentZoom = target;
    try {
      await controller.setZoomLevel(target);
    } catch (e) {
      debugPrint('Zoom error: $e');
    }
  }

  /// ডাবল-ট্যাপে zoom রিসেট।
  Future<void> _resetZoom() async {
    final controller = _controller;
    if (controller == null || _maxZoom <= _minZoom) return;
    _currentZoom = _minZoom;
    try {
      await controller.setZoomLevel(_minZoom);
    } catch (_) {
      // ignore — কিছু ডিভাইসে zoom সাপোর্ট নেই
    }
    if (mounted) setState(() {});
  }

  /// front/back ক্যামেরা বদল।
  Future<void> _switchCamera() async {
    final cameras = _cameras;
    if (cameras == null || cameras.length < 2 || _switching) return;
    setState(() => _switching = true);
    try {
      final nextIndex = (_cameraIndex + 1) % cameras.length;
      await _controller?.dispose();
      _controller = null;
      _isTorchOn = false;
      setState(() => _init = false);
      await _initController(nextIndex);
    } catch (e) {
      debugPrint('Camera switch error: $e');
      if (mounted) {
        setState(() => _error = _friendlyCameraError(e));
      }
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  /// torch/flash টগল (front ক্যামেরায় সাপোর্ট না থাকলে silently ignore)।
  Future<void> _toggleTorch() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller
          .setFlashMode(_isTorchOn ? FlashMode.off : FlashMode.torch);
      if (mounted) setState(() => _isTorchOn = !_isTorchOn);
    } catch (e) {
      debugPrint('Flash error: $e');
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

  Future<void> _takePicture() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        _saving ||
        !_readyToCapture) {
      return;
    }
    // await-এর আগেই capture — context যেন async gap-এ ব্যবহার না হয়
    final provider = Provider.of<StudentProvider>(context, listen: false);
    setState(() => _saving = true);
    try {
      final XFile file = await controller.takePicture();
      if (!mounted) return;

      final isPhoto = widget.docType == DocType.PHOTO;
      // Camera plugin-এর cache পরিষ্কার হয়ে যেতে পারে, তাই review/crop-এর আগে
      // original capture-টি temporary storage-এ রাখি। Final JPEG কখনও এটিকে বদলায় না।
      String? originalCapturePath;
      int qualityFlags = 0;
      if (isPhoto && provider.isPassportMode) {
        originalCapturePath =
            await StorageService.temporaryCapturePath(widget.student.dakhila);
        await File(file.path).copy(originalCapturePath);
        qualityFlags = await assessPhotoQualityInIsolate(
          await File(originalCapturePath).readAsBytes(),
        );
      }
      // Phase 7: নতুন ছবি v2 ফোল্ডার-লেআউটে সেভ হয়
      // (ছাত্র-প্রতি ফোল্ডার: v2/ক্লাস/Forik_N/দাখিলা/TYPE/দাখিলা.jpg)
      final savePath = await StorageService.documentPath(
        widget.student.className,
        widget.student.forikNo,
        widget.student.dakhila,
        widget.docType,
        'jpg',
      );

      if (isPhoto && provider.isPassportMode) {
        // Passport size: 431×531 — isolate-এ center crop + auto-enhance + resize
        final bytes = await File(originalCapturePath!).readAsBytes();
        final processed = await processPassportInIsolate(
          bytes,
          provider.passportPreset,
          provider.isAutoEnhancementEnabled,
        );
        if (processed != null) {
          await File(savePath).writeAsBytes(processed);
        } else {
          await File(file.path).copy(savePath);
        }
      } else {
        // Original mode / ডকুমেন্ট মোড — পুরো পেজ যেমন তোলা তেমন সেভ
        await File(file.path).copy(savePath);
      }

      if (isPhoto) {
        // PHOTO: image_path mirror + PHOTO doc (updateImage-ই সামলায়)
        await DatabaseHelper.instance
            .updateImage(widget.student.dakhila, savePath);
      } else {
        // BIRTH/FORM: documents টেবিলে সেভ
        await provider.markDocumentSaved(
            widget.student.dakhila, widget.docType, savePath);
      }
      if (!mounted) return;

      // গ্যালারিতেও সেভ (best-effort — ব্যর্থ হলে অ্যাপ-ফোল্ডারের কপি থাকে);
      // PHOTO: পুরনো নাম (281.jpg) বজায় থাকে যাতে retake-এ replace হয়;
      // BIRTH/FORM: 281_BIRTH.jpg / 281_FORM.jpg
      final galleryName = isPhoto
          ? '${widget.student.dakhila}.jpg'
          : '${widget.student.dakhila}_${widget.docType.name}.jpg';
      await GallerySaver.saveToGallery(
        filePath: savePath,
        fileName: galleryName,
      );
      if (!mounted) return;

      // ক্যাপচার ফিডব্যাক: হ্যাপটিক + সিস্টেম সাউন্ড
      HapticFeedback.mediumImpact();
      SystemSound.play(SystemSoundType.alert);

      if (isPhoto) {
        await provider.markCaptured(widget.student.dakhila, savePath);
        if (!mounted) return;

        // রিভিউ দেখাই — ভুল ছবি হলে আবার তোলা যাবে;
        // serial mode-এ পরের দাখিলায় সরাসরি যাওয়া যাবে।
        final next = provider.isSerialMode
            ? provider.getNext(widget.student.dakhila)
            : null;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ReviewScreen(
              student: widget.student,
              imagePath: savePath,
              originalCapturePath: originalCapturePath,
              qualityFlags: qualityFlags,
              next: next,
            ),
          ),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${widget.docType.label} সেভ হয়েছে ✓')),
        );
        Navigator.pop(context); // ড্যাশবোর্ডে ফেরত
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

  Widget _controlButton(IconData icon, VoidCallback? onTap,
      {Color color = Colors.white}) {
    return Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: color, size: 26),
        ),
      ),
    );
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
    final provider = context.watch<StudentProvider>();
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.docType == DocType.PHOTO
            ? 'দাখিলা: ${widget.student.dakhila} — ${widget.student.stuName}'
            : '${widget.docType.label}: ${widget.student.dakhila} — '
                '${widget.student.stuName}'),
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
                      child: GestureDetector(
                        onScaleStart: (_) => _baseZoom = _currentZoom,
                        onScaleUpdate: _onZoomUpdate,
                        onDoubleTap: _resetZoom,
                        child: CameraPreview(_controller!),
                      ),
                    ),
                    // চূড়ান্ত 431×531 crop-এর ভিজ্যুয়াল গাইড — ছবি তোলার
                    // আগেই মুখ/কাঁধ সঠিক জায়গায় রাখা সহজ হয়।
                    if (widget.docType == DocType.PHOTO &&
                        provider.isPassportMode)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Center(
                            // একই AspectRatio ব্যবহার করায় guide-টি letterbox
                            // বাদ দিয়ে CameraPreview-এর দৃশ্যমান অংশেই থাকে।
                            child: AspectRatio(
                              aspectRatio: _controller!.value.aspectRatio,
                              child: Center(
                                child: FractionallySizedBox(
                                  widthFactor: 0.62,
                                  child: AspectRatio(
                                    aspectRatio: 431 / 531,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                            color: Colors.white70, width: 2),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Align(
                                        alignment: Alignment.topCenter,
                                        child: Padding(
                                          padding: EdgeInsets.only(top: 5),
                                          child: Text(
                                            '431 × 531',
                                            style: TextStyle(
                                              color: Colors.white70,
                                              fontSize: 11,
                                              shadows: [
                                                Shadow(
                                                    color: Colors.black,
                                                    blurRadius: 3),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    // 3x3 rule-of-thirds grid — মুখ মাঝখানে রাখতে সাহায্য করে
                    if (provider.isGridMode)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: _GridPainter(
                                Colors.white.withValues(alpha: 0.4)),
                          ),
                        ),
                      ),
                    if (_currentZoom > _minZoom + 0.05)
                      Positioned(
                        bottom: 120,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              '${_currentZoom.toStringAsFixed(1)}x',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13),
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      top: 16,
                      left: 16,
                      right: 72,
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
                                widget.docType != DocType.PHOTO
                                    ? 'ডকুমেন্ট মোড (পুরো পেজ সেভ হবে)'
                                    : p.isPassportMode
                                        ? 'পাসপোর্ট (431×531, ${p.isAutoEnhancementEnabled ? p.passportPreset.label : 'Natural'})'
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
                      top: 16,
                      right: 8,
                      child: Column(
                        children: [
                          if ((_cameras?.length ?? 0) > 1)
                            _controlButton(Icons.switch_camera_outlined,
                                _switching ? null : _switchCamera),
                          if (_cameras != null &&
                              _cameras![_cameraIndex].lensDirection !=
                                  CameraLensDirection.front)
                            _controlButton(
                              _isTorchOn ? Icons.flash_on : Icons.flash_off,
                              _toggleTorch,
                              color: _isTorchOn
                                  ? Colors.amberAccent
                                  : Colors.white,
                            ),
                          _controlButton(
                            provider.isGridMode
                                ? Icons.grid_on
                                : Icons.grid_off,
                            () => provider.setGridMode(!provider.isGridMode),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      bottom: 30,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: _saving || !_readyToCapture
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

/// 3x3 rule-of-thirds গ্রিড ওভারলে — পাসপোর্ট ছবিতে মুখ মাঝখানে রাখতে সাহায্য করে।
class _GridPainter extends CustomPainter {
  final Color color;

  _GridPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0;
    for (int i = 1; i < 3; i++) {
      final double dx = size.width * i / 3;
      final double dy = size.height * i / 3;
      canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), paint);
      canvas.drawLine(Offset(0, dy), Offset(size.width, dy), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) => oldDelegate.color != color;
}
