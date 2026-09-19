 import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/document.dart';
import '../services/export_service.dart';
import '../widgets/report_form_print_view.dart';
import 'widget_capture.dart';

/// পূর্ণ রিপোর্ট ফরম → PDF (প্রিন্ট/শেয়ার)।
///
/// পদ্ধতি: প্রিন্ট-বান্ধব উইজেট → অফস্ক্রিন PNG (Flutter নিজেই বাংলা
/// যুক্তাক্ষর + আরবী + ইংরেজি নিখুঁতভাবে শেপ করে) → A4-অনুপাতে স্লাইস →
/// JPEG → pdf প্যাকেজে পেজ। pdf প্যাকেজের বাংলা-শেপিং সীমাবদ্ধতা এভাবে এড়ানো যায়।
class ReportPdf {
  ReportPdf._();

  /// A4 প্রস্থ @ 96dpi — ক্যাপচারের লজিক্যাল প্রস্থ।
  static const double _a4LogicalWidth = 794;
  static const double _pixelRatio = 2.5; // ≈ 240 DPI

  static Future<String> export({
    required OverlayState overlay,
    required StudentWithDocs swd,
    required String institutionName,
    String? institutionLogoPath,
    required String teacherName,
    required String teacherMobile,
    String? outDir,
  }) async {
    final dir = outDir ?? await ExportService.ensureExportDir();
    final s = swd.student;

    // ছবি আগে থেকে ডিকোড — ক্যাপচারে ফাঁকা ঘর রোধ
    final warmup = <ImageProvider>[];
    if (institutionLogoPath != null &&
        File(institutionLogoPath).existsSync()) {
      warmup.add(FileImage(File(institutionLogoPath)));
    }
    if (s.imagePath != null && File(s.imagePath!).existsSync()) {
      warmup.add(FileImage(File(s.imagePath!)));
    }

    // ১) অফস্ক্রিন ক্যাপচার (Flutter-এর নিজস্ব টেক্সট-স্ট্যাক দিয়ে শেপিং)
    final png = await WidgetCapture.capturePng(
      overlay: overlay,
      logicalWidth: _a4LogicalWidth,
      pixelRatio: _pixelRatio,
      warmupImages: warmup,
      builder: (_) => ReportFormPrintView(
        swd: swd,
        institutionName: institutionName,
        institutionLogoPath: institutionLogoPath,
        teacherName: teacherName,
        teacherMobile: teacherMobile,
      ),
    );

    // ২) A4-অনুপাতে স্লাইস + JPEG (isolate-এ)
    final pages = await Isolate.run(() => _sliceToJpegs(png));

    // ৩) PDF — প্রতি স্লাইস এক A4 পেজ (শূন্য মার্জিন, পূর্ণ-ব্লিড)
    final doc = pw.Document();
    for (final page in pages) {
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Image(pw.MemoryImage(page), fit: pw.BoxFit.fill),
      ));
    }

    final path = p.join(
      dir,
      'Report_Form_${_sanitize(s.dakhila)}_${_stamp()}.pdf',
    );
    await File(path).writeAsBytes(await doc.save(), flush: true);
    return path;
  }

  /// লম্বা PNG → A4-অনুপাতের পেজ-স্লাইস (শেষ পেজ সাদা-প্যাডেড) → JPEG।
  static List<Uint8List> _sliceToJpegs(Uint8List pngBytes) {
    final full = img.decodePng(pngBytes);
    if (full == null) throw StateError('PNG ডিকোড ব্যর্থ');
    final w = full.width;
    final pageH = (w * 297 / 210).round();
    final count = (full.height + pageH - 1) ~/ pageH;
    final out = <Uint8List>[];
    for (var i = 0; i < count; i++) {
      final y = i * pageH;
      final h = math.min(pageH, full.height - y);
      final cropped = img.copyCrop(full, x: 0, y: y, width: w, height: h);
      if (h == pageH) {
        out.add(Uint8List.fromList(img.encodeJpg(cropped, quality: 88)));
      } else {
        final page = img.Image(width: w, height: pageH);
        img.fill(page, color: img.ColorRgb8(255, 255, 255));
        img.compositeImage(page, cropped, dstX: 0, dstY: 0);
        out.add(Uint8List.fromList(img.encodeJpg(page, quality: 88)));
      }
    }
    return out;
  }

  static String _sanitize(String name) =>
      name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();

  static String _stamp() {
    final now = DateTime.now();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '${now.year}-$m-$d';
  }
}