import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:csv/csv.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../db/database_helper.dart';
import '../models/document.dart';
import '../services/storage_service.dart';

/// Phase 8: অফিস এক্সপোর্ট v2 — doc-aware (PHOTO/BIRTH/FORM)।
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

  /// স্কোপের সব ছাত্র + ডকুমেন্ট ম্যাপ লোড
  static Future<List<StudentWithDocs>> _loadScope(
      {String? classFilter, String? forikFilter}) async {
    final students = await DatabaseHelper.instance
        .getAllStudents(classFilter: classFilter, forikFilter: forikFilter);
    final docsMap = await DatabaseHelper.instance.getAllDocumentsMap();
    return students
        .map((s) => StudentWithDocs(
              student: s,
              docs: docsMap[s.dakhila] ?? const <DocType, StudentDocument>{},
            ))
        .toList();
  }

  /// ছাত্রের বিদ্যমান ডকুমেন্ট ফাইলগুলো (ডিস্কে আছে শুধু)
  static List<StudentDocument> _existingDocs(StudentWithDocs swd) =>
      swd.docs.values
          .whereType<StudentDocument>()
          .where((d) => File(d.filePath).existsSync())
          .toList();

  /// Status report CSV v2 (UTF-8 BOM): প্রতি ছাত্রের Photo/Birth/Form স্ট্যাটাস।
  static String _statusCsvContent(List<StudentWithDocs> scope) {
    String yn(bool v) => v ? 'yes' : 'no';
    final rows = <List<dynamic>>[
      [
        'Dakhila',
        'Name',
        'Class',
        'Forik',
        'Photo',
        'Birth',
        'Form',
        'MissingCount'
      ],
      ...scope.map((swd) => [
            swd.student.dakhila,
            swd.student.stuName,
            swd.student.className,
            swd.student.forikNo,
            yn(swd.hasDoc(DocType.PHOTO)),
            yn(swd.hasDoc(DocType.BIRTH)),
            yn(swd.hasDoc(DocType.FORM)),
            3 - swd.completedCount,
          ]),
    ];
    return '\uFEFF${const ListToCsvConverter().convert(rows)}';
  }

  /// summary.txt: ফরিক-ভিত্তিক হিসাব
  static String _summaryContent(List<StudentWithDocs> scope) {
    final byForik = <String, List<StudentWithDocs>>{};
    for (final swd in scope) {
      byForik.putIfAbsent(swd.student.forikNo, () => []).add(swd);
    }
    final buf = StringBuffer();
    var totalStudents = 0;
    var totalDone = 0;
    for (final forik in byForik.keys.toList()..sort()) {
      final list = byForik[forik]!;
      final done = list.fold<int>(0, (sum, s) => sum + s.completedCount);
      totalStudents += list.length;
      totalDone += done;
      buf.writeln(
          'Forik $forik: ${list.length} students, $done/${list.length * 3} docs done');
    }
    buf.writeln();
    buf.writeln('Total: $totalStudents students, '
        '$totalDone/${scope.length * 3} docs done');
    return buf.toString();
  }

  /// Phase 8 — ZIP v2: ছাত্র-প্রতি ফোল্ডারে সব ডক (PHOTO/BIRTH/FORM)
  /// + `_reports/missing.csv` + `_reports/summary.txt`।
  /// Streaming encoder — হাজার খানেক ফাইলেও মেমোরি নিরাপদ।
  static Future<String> exportZip({
    String? classFilter,
    String? forikFilter,
    String? outDir,
    void Function(int done, int total)? onProgress,
  }) async {
    final dir = outDir ?? await ensureExportDir();
    final scope =
        await _loadScope(classFilter: classFilter, forikFilter: forikFilter);
    final zipPath = p.join(
      dir,
      'Dakhila_${_scopeTag(classFilter: classFilter, forikFilter: forikFilter)}_${_stamp()}.zip',
    );

    // আগে সব entry যাচাই — কিছু না থাকলে খালি zip-ই তৈরি হবে না
    final docFiles = <(String, String)>[]; // (zipEntry, sourcePath)
    for (final swd in scope) {
      final s = swd.student;
      final classDir = _sanitize(s.className.isEmpty ? 'Unknown' : s.className);
      final studentDir =
          '$classDir/Forik_${_sanitize(s.forikNo)}/${s.dakhila}_${_sanitize(s.stuName)}';
      for (final d in _existingDocs(swd)) {
        docFiles.add((
          '$studentDir/${StorageService.fileName(s.dakhila, d.type, d.ext)}',
          d.filePath
        ));
      }
    }
    if (docFiles.isEmpty) {
      throw StateError('এই স্কোপে কোনো ডকুমেন্ট ফাইল নেই');
    }

    final encoder = ZipFileEncoder();
    encoder.create(zipPath);
    var done = 0;
    for (final (entry, source) in docFiles) {
      encoder.addFile(File(source), entry);
      done++;
      onProgress?.call(done, docFiles.length);
    }
    final statusCsv = utf8.encode(_statusCsvContent(scope));
    encoder.addArchiveFile(
        ArchiveFile('_reports/missing.csv', statusCsv.length, statusCsv));
    final summary = utf8.encode(_summaryContent(scope));
    encoder.addArchiveFile(
        ArchiveFile('_reports/summary.txt', summary.length, summary));
    encoder.close();
    return zipPath;
  }

  /// Phase 8 — Status CSV v2: প্রতি ছাত্রের Photo/Birth/Form স্ট্যাটাস
  /// + MissingCount (Excel-friendly, UTF-8 BOM)।
  static Future<String> exportMissingCsv({
    String? classFilter,
    String? forikFilter,
    String? outDir,
  }) async {
    final dir = outDir ?? await ensureExportDir();
    final scope =
        await _loadScope(classFilter: classFilter, forikFilter: forikFilter);
    if (scope.isEmpty) {
      throw StateError('এই স্কোপে কোনো ছাত্র নেই');
    }
    final csvPath = p.join(
      dir,
      'Status_Report_${_scopeTag(classFilter: classFilter, forikFilter: forikFilter)}_${_stamp()}.csv',
    );
    await File(csvPath).writeAsString(_statusCsvContent(scope), encoding: utf8);
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
    final scope =
        await _loadScope(classFilter: classFilter, forikFilter: forikFilter);
    final captured = scope
        .map((swd) => swd.student)
        .where((s) =>
            s.isCaptured == 1 &&
            s.imagePath != null &&
            File(s.imagePath!).existsSync())
        .toList();
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

  /// Phase 8: একজন ছাত্রের সব ডক এক PDF-এ (প্রতি ডক এক A4 পেজ)।
  /// ইমেজ ডক (JPG/PNG) এমবেড হয়; PDF ডক থাকলে নোট পেজ যোগ হয়।
  static Future<String> exportStudentMergedPdf({
    required String dakhila,
    String? outDir,
  }) async {
    final dir = outDir ?? await ensureExportDir();
    final docsMap = await DatabaseHelper.instance.getAllDocumentsMap();
    final docs = docsMap[dakhila];
    if (docs == null || docs.isEmpty) {
      throw StateError('এই ছাত্রের কোনো ডকুমেন্ট নেই');
    }
    final ordered = [DocType.PHOTO, DocType.BIRTH, DocType.FORM]
        .map((t) => docs[t])
        .whereType<StudentDocument>()
        .toList();
    if (ordered.isEmpty) {
      throw StateError('এই ছাত্রের কোনো ডকুমেন্ট নেই');
    }

    final doc = pw.Document();
    for (final d in ordered) {
      if (d.ext == 'pdf') {
        // PDF ডক pdf প্যাকেজে এমবেড করা যায় না — নোট পেজ
        doc.addPage(pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (_) => pw.Center(
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Text('${d.type.name} (PDF)',
                    style: pw.TextStyle(
                        fontSize: 16, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 8),
                pw.Text('Separate file: ${d.filePath}',
                    style: const pw.TextStyle(fontSize: 10)),
              ],
            ),
          ),
        ));
        continue;
      }
      final bytes = await File(d.filePath).readAsBytes();
      final image = pw.MemoryImage(bytes);
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (_) => pw.Column(children: [
          pw.Text('${d.type.name} — $dakhila',
              style:
                  pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Expanded(
            child: pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
          ),
        ]),
      ));
    }

    final pdfPath = p.join(dir, 'Merged_${_sanitize(dakhila)}_${_stamp()}.pdf');
    await File(pdfPath).writeAsBytes(await doc.save());
    return pdfPath;
  }
}
