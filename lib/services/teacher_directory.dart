import 'package:excel/excel.dart';

import '../models/teacher.dart';
import '../utils/contact_helper.dart';

/// শিক্ষক-তালিকার লজিক — bundled `assets/Negran_Teacher_Name.xlsx`
/// (Sheet: "Teacher Name") পার্স + ছাত্রের ক্লাস+ফরিক মিলিয়ে শিক্ষক খোঁজা।
///
/// ডেটা-সোর্স এখন DB-র `teachers` টেবিল (স্তর ৪ — অ্যাপে সম্পাদনাযোগ্য);
/// এই ক্লাসে শুধু pure ফাংশন — পার্স, নরমালাইজ, ম্যাচ।
class TeacherDirectory {
  TeacherDirectory._();

  /// বান্ডেল করা সিড-ফাইল — DB-র teachers টেবিল প্রথমবার চালু/আপগ্রেডে
  /// খালি থাকলে এখান থেকে ভরা হয় (DB helper ব্যবহার করে)।
  static const String assetPath = 'assets/Negran_Teacher_Name.xlsx';

  /// হেডার → ফিল্ড (case-insensitive; স্পেস→আন্ডারস্কোর করা হয়)।
  static const Map<String, String> _headerMap = {
    'CLASS_NAME': 'CLASS_NAME',
    'FORIK_NAME': 'FORIK_NAME',
    'FORIK': 'FORIK_NAME',
    'FORIK_NO': 'FORIK_NAME',
    'TEACHER_NAME_B': 'TEACHER_NAME_B',
    'TEACHER_NAME_BANGLA': 'TEACHER_NAME_B',
    'TEACHER_NAME': 'TEACHER_NAME',
    'TEACHER': 'TEACHER_NAME',
    'MOBILE_NO': 'MOBILE_NO',
    'MOBILE': 'MOBILE_NO',
    'PHONE': 'MOBILE_NO',
    'PHONE_NO': 'MOBILE_NO',
  };

  /// টেক্সট নরমালাইজ — একাধিক স্পেস/ট্যাব → এক স্পেস + trim
  /// ("বোর্ড-  জানুয়ারী" → "বোর্ড- জানুয়ারী")।
  static String normText(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

  /// মোবাইল নরমালাইজ — [ContactHelper.normalizeLocalMobile] দিয়ে; অসম্পূর্ণ
  /// (<১০ ডিজিট) হলে খালি (কল/হোয়াটসঅ্যাপ বাটন লুকাবে)।
  static String normMobile(String raw) {
    final digits = ContactHelper.normalizeLocalMobile(raw);
    return digits.length >= 10 ? digits : '';
  }

  /// xlsx bytes → TeacherInfo তালিকা। প্রথম যে শিটে CLASS_NAME কলাম
  /// পাওয়া যায় সেটাই ডেটা ধরা হয় (ExcelParser-এর মতো)।
  static List<TeacherInfo> parseFromBytes(List<int> bytes) {
    final excel = Excel.decodeBytes(bytes);
    for (final sheet in excel.tables.values) {
      final rows = sheet.rows;
      if (rows.isEmpty) continue;

      final header = rows.first;
      final col = <int, String>{};
      for (var c = 0; c < header.length; c++) {
        final raw = header[c]?.value?.toString().trim() ?? '';
        final key = raw.toUpperCase().replaceAll(' ', '_');
        final mapped = _headerMap[key];
        if (mapped != null) col[c] = mapped;
      }
      final classCol = col.entries
          .firstWhere((e) => e.value == 'CLASS_NAME', orElse: () => const MapEntry(-1, ''))
          .key;
      if (classCol < 0) continue;

      final out = <TeacherInfo>[];
      for (var r = 1; r < rows.length; r++) {
        final row = rows[r];
        String cell(String? field) {
          if (field == null) return '';
          final c = col.entries
              .firstWhere((e) => e.value == field, orElse: () => const MapEntry(-1, ''))
              .key;
          if (c < 0 || c >= row.length) return '';
          final v = row[c]?.value;
          return v == null ? '' : v.toString();
        }

        final className = normText(cell('CLASS_NAME'));
        final nameBn = normText(cell('TEACHER_NAME_B'));
        final nameEn = normText(cell('TEACHER_NAME'));
        if (className.isEmpty || (nameBn.isEmpty && nameEn.isEmpty)) {
          continue; // খালি/অসম্পূর্ণ রো স্কিপ
        }
        out.add(TeacherInfo(
          className: className,
          forik: normText(cell('FORIK_NAME')),
          nameBn: nameBn,
          nameEn: nameEn,
          mobile: normMobile(cell('MOBILE_NO')),
        ));
      }
      if (out.isNotEmpty) return out;
    }
    return const <TeacherInfo>[];
  }

  /// ছাত্রের ক্লাস+ফরিক দিয়ে দায়িত্বপ্রাপ্ত শিক্ষক।
  /// ১) ক্লাস+ফরিক exact → ২) ক্লাসের ফরিক-উদাসীন এন্ট্রি → ৩) null।
  static TeacherInfo? find(
      List<TeacherInfo>? teachers, String className, String forikNo) {
    if (teachers == null || teachers.isEmpty) return null;
    final cls = normText(className);
    if (cls.isEmpty) return null;
    final forik = normText(forikNo);
    TeacherInfo? classLevel;
    for (final t in teachers) {
      if (t.className != cls) continue;
      if (t.forik.isEmpty) {
        classLevel ??= t;
      } else if (forik.isNotEmpty && _sameForik(t.forik, forik)) {
        return t; // ফরিক-নির্দিষ্ট ম্যাচ — সর্বোচ্চ অগ্রাধিকার
      }
    }
    return classLevel;
  }

  static bool _sameForik(String a, String b) {
    if (a == b) return true;
    final na = int.tryParse(a);
    final nb = int.tryParse(b);
    return na != null && nb != null && na == nb; // "01" ও "1" এক
  }
}
