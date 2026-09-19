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
    // রিপোর্ট ফরম: পরীক্ষার গড় নম্বর + ঠিকানা
    'AVG_NUM_MONTH': 'AVG_NUM_MONTH',
    'AVG_NUM_1ST': 'AVG_NUM_1ST',
    'AVG_NUM_2ND': 'AVG_NUM_2ND',
    'AVG_NUM_FINAL': 'AVG_NUM_FINAL',
    'MOTHER_NAME': 'MOTHER_NAME',
    'BIRTH_DATE': 'BIRTH_DATE',
    'DOB': 'BIRTH_DATE',
    'BIRTH_CERTIFICATE_NO': 'BIRTH_CERTIFICATE_NO',
    'BIRTH_CERT_NO': 'BIRTH_CERTIFICATE_NO',
    'ID_BIRTH_NO': 'BIRTH_CERTIFICATE_NO',
    'PAR_ADD_VILL': 'PAR_ADD_VILL',
    'VILLAGE': 'PAR_ADD_VILL',
    'PAR_ADD_PO': 'PAR_ADD_PO',
    'POST_OFFICE': 'PAR_ADD_PO',
    'PAR_ADD_PS': 'PAR_ADD_PS',
    'THANA': 'PAR_ADD_PS',
    'PAR_ADD_DIST': 'PAR_ADD_DIST',
    'DISTRICT': 'PAR_ADD_DIST',
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

  /// রাউন্ড-ট্রিপ ম্যাপ: এক্সপোর্ট xlsx-এর বাংলা হেডার → DB কলাম।
  /// শুধু নিরাপদ কলাম — দাখিলা/ক্লাস/ফরিক (আইডেন্টিটি, ফাইল-পাথ-নির্ভর)
  /// ও ডক-স্ট্যাটাস/ঠিকানা-কম্পোজিট ইচ্ছাকৃতভাবে বাদ।
  static const Map<String, String> _roundTripMap = {
    'নাম (বাংলা)': 'stu_name',
    'নাম (ইংরেজি)': 'stu_name_en',
    'নাম (আরবী)': 'stu_name_ar',
    'পিতা (বাংলা)': 'father_name',
    'পিতা (ইংরেজি)': 'father_name_en',
    'পিতা (আরবী)': 'father_name_ar',
    'মাতা (বাংলা)': 'mother_name',
    'মাতা (ইংরেজি)': 'mother_name_en',
    'মাতা (আরবী)': 'mother_name_ar',
    'মোবাইল': 'guardian_mobile',
    'লেভেল': 'class_level',
    'মারহালা': 'marhala',
    'পরীক্ষার বছর': 'exam_year',
    'দাখিলা বছর': 'dakhila_year',
    'জন্ম তারিখ': 'birth_date',
    'জন্মসনদ নম্বর': 'birth_certificate_no',
    'মাসিক': 'avg_num_month',
    'প্রথম সাময়িক': 'avg_num_1st',
    'দ্বিতীয় সাময়িক': 'avg_num_2nd',
    'বার্ষিক': 'avg_num_final',
  };

  /// এক্সপোর্ট করা xlsx → ছাত্র-আপডেট (দাখিলা + শুধু অ-খালি সেল-মান)।
  /// খালি সেল = অ্যাপের বর্তমান মান অক্ষত — Excel-এ শুধু যা বদলানো হয়েছে
  /// সেটাই কার্যকর হয়।
  static List<({String dakhila, Map<String, dynamic> values})>
      parseUpdateFromBytes(List<int> bytes) {
    final excel = Excel.decodeBytes(bytes);
    for (final sheet in excel.tables.values) {
      final rows = sheet.rows;
      if (rows.isEmpty) continue;

      final header = rows.first;
      var dakhilaCol = -1;
      final colMap = <int, String>{};
      for (var c = 0; c < header.length; c++) {
        final raw = header[c]?.value?.toString().trim() ?? '';
        if (raw == 'দাখিলা') dakhilaCol = c;
        final dbCol = _roundTripMap[raw];
        if (dbCol != null) colMap[c] = dbCol;
      }
      if (dakhilaCol == -1) continue; // এই শিট আমাদের এক্সপোর্ট-ফরম্যাট নয়

      final out = <({String dakhila, Map<String, dynamic> values})>[];
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
        if (dakhila == null) continue; // খালি রো স্কিপ
        final values = <String, dynamic>{};
        colMap.forEach((col, dbCol) {
          final v = cell(col);
          if (v != null) values[dbCol] = v; // অ-খালি সেলই আপডেট
        });
        if (values.isEmpty) continue; // কিছু বদলানো হয়নি
        out.add((dakhila: dakhila, values: values));
      }
      if (out.isNotEmpty) return out;
    }
    throw const FormatException(
        'ফাইলে "দাখিলা" কলামসহ এক্সপোর্ট-ফরম্যাট পাওয়া যায়নি');
  }

  /// ভারী পার্সিং isolate-এ।
  static Future<List<({String dakhila, Map<String, dynamic> values})>>
      parseUpdateFromBytesInIsolate(List<int> bytes) =>
          Isolate.run(() => parseUpdateFromBytes(bytes));
}
