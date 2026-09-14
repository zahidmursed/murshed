import 'dart:convert';

class Student {
  final String dakhila;
  final String stuName;
  final String className;
  final String forikNo;
  final String fatherName;
  final String dakhilaYear;
  String? imagePath;
  int isCaptured;

  Student({
    required this.dakhila,
    required this.stuName,
    required this.className,
    required this.forikNo,
    required this.fatherName,
    required this.dakhilaYear,
    this.imagePath,
    this.isCaptured = 0,
  });

  factory Student.fromJson(Map<String, dynamic> j) {
    return Student(
      dakhila: j['DAKHILA']?.toString() ?? '',
      stuName: j['STU_NAME'] ?? '',
      className: j['CLASS_NAME'] ?? '',
      forikNo: j['FORIK_NO']?.toString() ?? '',
      fatherName: j['FATHER_NAME'] ?? '',
      dakhilaYear: j['DAKHILA_YEAR']?.toString() ?? '2025',
      imagePath: j['image_path'],
      isCaptured: j['is_captured'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'dakhila': dakhila,
      'stu_name': stuName,
      'class_name': className,
      'forik_no': forikNo,
      'father_name': fatherName,
      'dakhila_year': dakhilaYear,
      'image_path': imagePath,
      'is_captured': isCaptured,
    };
  }

  /// [raw] JSON টেক্সট থেকে DB-insert-যোগ্য ম্যাপের লিস্ট তৈরি করে।
  /// বড় ফাইল (1.6MB+) ডিকোড background isolate-এ চালানোর জন্য pure/static রাখা হয়েছে।
  static List<Map<String, dynamic>> parseJsonToMaps(String raw) {
    final List<dynamic> list = json.decode(raw) as List<dynamic>;
    return list
        .map((e) => Student.fromJson(e as Map<String, dynamic>).toMap())
        .toList();
  }
}
