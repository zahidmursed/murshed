import 'dart:isolate';

import 'package:excel/excel.dart';

import '../models/student.dart';

/// Phase 5B: Excel (.xlsx) ইমপোর্ট পার্সার।
/// হেডার কেস-ইনসেনসিটিভ; JSON key-গুলোই মানা হয় (DAKHILA, STU_NAME...)।
class ExcelParser {
  ExcelParser._();

  static const Map<String, String> _headerMap = {
    'DAKHILA': 'DAKHILA',
    'STU_NAME': 'STU_NAME',
    'STUDENT_NAME': 'STU_NAME',
    'NAME': 'STU_NAME',
    'CLASS_NAME': 'CLASS_NAME',
    'CLASS': 'CLASS_NAME',
    'FORIK_NO': 'FORIK_NO',
    'FORIK': 'FORIK_NO',
    'FATHER_NAME': 'FATHER_NAME',
    'FATHER': 'FATHER_NAME',
    'GAR_MOB_NO': 'GAR_MOB_NO',
    'GUARDIAN_MOBILE': 'GAR_MOB_NO',
    'MOBILE': 'GAR_MOB_NO',
    'MOBILE_NO': 'GAR_MOB_NO',
    'PHONE': 'GAR_MOB_NO',
    'DAKHILA_YEAR': 'DAKHILA_YEAR',
    'YEAR': 'DAKHILA_YEAR',
    // ফিক্স: Excel ইমপোর্টেও শিক্ষা-ক্রম/মারহালা/পরীক্ষার বছর হারাত না —
    // ক্লাস dropdown-এর level-order অ্যাসেন্ডিং এগুলোর উপর নির্ভর করে।
    'CLASS_LEVEL': 'CLASS_LEVEL',
    'MARHALA': 'MARHALA',
    'EXAM_YEAR': 'EXAM_YEAR',
  };

  /// xlsx bytes → DB-রেডি ম্যাপ (Student.toMap স্কিমা)।
  /// প্রথম যে শিটে DAKHILA কলাম পাওয়া যায়, সেটাই ডেটা ধরা হয়।
  static List<Map<String, dynamic>> parseFromBytes(List<int> bytes) {
    final excel = Excel.decodeBytes(bytes);
    for (final sheet in excel.tables.values) {
      final rows = sheet.rows;
      if (rows.isEmpty) continue;

      // হেডার রো → কলাম ইনডেক্স
      final header = rows.first;
      final colKey = <int, String>{};
      for (var c = 0; c < header.length; c++) {
        final raw = header[c]?.value?.toString().trim() ?? '';
        final key = raw.toUpperCase().replaceAll(' ', '_');
        final mapped = _headerMap[key];
        if (mapped != null) colKey[c] = mapped;
      }
      if (!colKey.containsValue('DAKHILA')) continue;

      final dakhilaCol =
          colKey.entries.firstWhere((e) => e.value == 'DAKHILA').key;

      final out = <Map<String, dynamic>>[];
      for (var r = 1; r < rows.length; r++) {
        final row = rows[r];
        String? cell(int col) {
          if (col >= row.length) return null;
          final v = row[col]?.value;
          if (v == null) return null;
          final t = v.toString().trim();
          return t.isEmpty ? null : t;
        }

        final dakhila = cell(dakhilaCol);
        if (dakhila == null || dakhila.isEmpty) continue; // খালি রো স্কিপ

        final j = <String, dynamic>{'DAKHILA': dakhila};
        colKey.forEach((col, key) {
          final v = cell(col);
          if (v != null) j[key] = v;
        });
        out.add(Student.fromJson(j).toMap());
      }
      if (out.isNotEmpty) return out;
    }
    throw const FormatException(
        'Excel ফাইলে DAKHILA কলাম সহ কোনো ডেটা পাওয়া যায়নি');
  }

  /// ভারী পার্সিং isolate-এ — UI freeze এড়াতে।
  static Future<List<Map<String, dynamic>>> parseFromBytesInIsolate(
          List<int> bytes) =>
      Isolate.run(() => parseFromBytes(bytes));
}
