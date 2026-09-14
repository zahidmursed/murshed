import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:csv/csv.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../db/database_helper.dart';
import '../models/student.dart';

/// Phase 5A: অফিস এক্সপোর্ট — Forik-wise ZIP, Missing CSV, PDF প্রিন্ট শিট।
/// স্কোপ: classFilter/forikFilter (মূল লিস্টের বর্তমান ফিল্টার থেকে আসে)।
class ExportService {
  ExportService._();

  /// এক্সপোর্ট ফাইল যেখানে বসে: <app-dir>/Export/
  static Future<String> ensureExportDir() async {
    final appDir = await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, 'Export'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  /// ফোল্ডার/ফাইলের নামে নিষিদ্ধ অক্ষর বাদ
  static String _sanitize(String name) =>
      name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();

  static String _scopeTag({String? classFilter, String? forikFilter}) {
    final c = (classFilter == null || classFilter.isEmpty)
        ? null
        : _sanitize(classFilter);
    final f = (forikFilter == null || forikFilter.isEmpty) ? null : forikFilter;
    if (c != null && f != null) return '${c}_F$f';
    if (c != null) return c;
    return 'All';
  }

  static String _stamp() {
    final now = DateTime.now();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '${now.year}-$m-$d';
  }

  static List<Student> _capturedWithFile(List<Student> students) => students
      .where((s) =>
          s.isCaptured == 1 &&
          s.imagePath != null &&
          File(s.imagePath!).existsSync())
      .toList();

  /// Missing report CSV (UTF-8 BOM — Excel-এ বাংলা ঠিক দেখাতে)
  static String _missingCsvContent(List<Student> students) {
    final missing = students.where((s) => s.isCaptured != 1).toList();
    final rows = <List<dynamic>>[
      ['Dakhila', 'Name', 'Class', 'Forik', 'Father'],
      ...missing.map(
          (s) => [s.dakhila, s.stuName, s.className, s.forikNo, s.fatherName]),
    ];
    return '\uFEFF${const ListToCsvConverter().convert(rows)}';
  }

  /// Forik-wise ফোল্ডার স্ট্রাকচারে সব তোলা ছবির ZIP
  /// (`ক্লাস/ফরিক_N/দাখিলা.jpg`) + ভিতরে `_missing_report.csv`।
  /// Streaming encoder — হাজার খানেক ছবিতেও মেমোরি নিরাপদ।
  static Future<String> exportZip({
    String? classFilter,
    String? forikFilter,
    String? outDir,
    void Function(int done, int total)? onProgress,
  }) async {
    final dir = outDir ?? await ensureExportDir();
    final all = await DatabaseHelper.instance
        .getAllStudents(classFilter: classFilter, forikFilter: forikFilter);
    final captured = _capturedWithFile(all);
    if (captured.isEmpty) {
      throw StateError('এই স্কোপে কোনো তোলা ছবি নেই');
    }
    final zipPath = p.join(
      dir,
      'DakhilaPhotos_${_scopeTag(classFilter: classFilter, forikFilter: forikFilter)}_${_stamp()}.zip',
    );

    final encoder = ZipFileEncoder();
    encoder.create(zipPath);
    var done = 0;
    for (final s in captured) {
      final className =
          _sanitize(s.className.isEmpty ? 'Unknown' : s.className);
      final entry = '$className/Forik_${s.forikNo}/${s.dakhila}.jpg';
      encoder.addFile(File(s.imagePath!), entry);
      done++;
      onProgress?.call(done, captured.length);
    }
    final missingCsv = utf8.encode(_missingCsvContent(all));
    encoder.addArchiveFile(
        ArchiveFile('_missing_report.csv', missingCsv.length, missingCsv));
    encoder.close();
    return zipPath;
  }

  /// যাদের ছবি তোলা হয়নি — CSV রিপোর্ট (Excel-friendly)।
  static Future<String> exportMissingCsv({
    String? classFilter,
    String? forikFilter,
    String? outDir,
  }) async {
    final dir = outDir ?? await ensureExportDir();
    final all = await DatabaseHelper.instance
        .getAllStudents(classFilter: classFilter, forikFilter: forikFilter);
    if (all.where((s) => s.isCaptured != 1).isEmpty) {
      throw StateError('দারুণ! এই স্কোপে সবার ছবি তোলা হয়ে গেছে');
    }
    final csvPath = p.join(
      dir,
      'Missing_Report_${_scopeTag(classFilter: classFilter, forikFilter: forikFilter)}_${_stamp()}.csv',
    );
    await File(csvPath).writeAsString(_missingCsvContent(all), encoding: utf8);
    return csvPath;
  }

  /// প্রিন্ট শিট: A4 পেজে ৯টি করে ছবি (3×3), নিচে দাখিলা নম্বর।
  /// নোট: pdf প্যাকেজে বাংলা shaping নেই — তাই ক্যাপশন শুধু দাখিলা নম্বর।
  static Future<String> exportPdfSheet({
    String? classFilter,
    String? forikFilter,
    String? outDir,
    void Function(int done, int total)? onProgress,
  }) async {
    final dir = outDir ?? await ensureExportDir();
    final all = await DatabaseHelper.instance
        .getAllStudents(classFilter: classFilter, forikFilter: forikFilter);
    final captured = _capturedWithFile(all);
    if (captured.isEmpty) {
      throw StateError('এই স্কোপে কোনো তোলা ছবি নেই');
    }

    final doc = pw.Document();
    const perPage = 9;
    var done = 0;
    for (var i = 0; i < captured.length; i += perPage) {
      final batch = captured.skip(i).take(perPage).toList();
      final cells = <pw.Widget>[];
      for (final s in batch) {
        final bytes = await File(s.imagePath!).readAsBytes();
        final image = pw.MemoryImage(bytes);
        cells.add(pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          children: [
            pw.Expanded(
              child: pw.Center(
                child: pw.Image(image, fit: pw.BoxFit.contain),
              ),
            ),
            pw.Text(
              s.dakhila,
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ));
        done++;
        onProgress?.call(done, captured.length);
      }
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(18),
        build: (_) => pw.GridView(
          crossAxisCount: 3,
          childAspectRatio: 0.72, // ছবি (3:4) + ক্যাপশন
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          children: cells,
        ),
      ));
    }

    final pdfPath = p.join(
      dir,
      'PrintSheet_${_scopeTag(classFilter: classFilter, forikFilter: forikFilter)}_${_stamp()}.pdf',
    );
    await File(pdfPath).writeAsBytes(await doc.save());
    return pdfPath;
  }
}
