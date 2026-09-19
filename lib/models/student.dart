import 'dart:convert';

class Student {
  final String dakhila;
  final String stuName;
  final String className;
  final String forikNo;
  final String fatherName;
  final String guardianMobile;
  final String dakhilaYear;
  final String classLevel;
  final String marhala;
  final String examYear;
  // পরীক্ষার গড় নম্বর (Data_basic.json → AVG_NUM_*)
  final String avgMonth; // মাসিক পরীক্ষা
  final String avg1st; // প্রথম সাময়িক
  final String avg2nd; // দ্বিতীয় সাময়িক
  final String avgFinal; // বার্ষিক
  final String motherName;
  final String birthDate; // ফরম্যাট: DD-MM-YYYY
  final String birthCertNo;
  // স্থায়ী ঠিকানা (Data_basic.json → PAR_ADD_*)
  final String addressVill;
  final String addressPo;
  final String addressPs;
  final String addressDist;
  // নামের ইংরেজি/আরবী রূপ — অ্যাপে হাতে/অটো-ফিলে ভরা হয় (DB v11)
  final String stuNameEn;
  final String stuNameAr;
  final String fatherNameEn;
  final String fatherNameAr;
  final String motherNameEn;
  final String motherNameAr;
  String? imagePath;
  int isCaptured;
  int totalDocs;

  Student({
    required this.dakhila,
    required this.stuName,
    required this.className,
    required this.forikNo,
    required this.fatherName,
    this.guardianMobile = '',
    required this.dakhilaYear,
    this.classLevel = '',
    this.marhala = '',
    this.examYear = '',
    this.motherName = '',
    this.birthDate = '',
    this.birthCertNo = '',
    this.avgMonth = '',
    this.avg1st = '',
    this.avg2nd = '',
    this.avgFinal = '',
    this.addressVill = '',
    this.addressPo = '',
    this.addressPs = '',
    this.addressDist = '',
    this.stuNameEn = '',
    this.stuNameAr = '',
    this.fatherNameEn = '',
    this.fatherNameAr = '',
    this.motherNameEn = '',
    this.motherNameAr = '',
    this.imagePath,
    this.isCaptured = 0,
    this.totalDocs = 0,
  });

  /// খালি অংশ বাদ দিয়ে ঠিকানার অংশগুলো কমা দিয়ে জোড়া।
  String get addressFull => [
        addressVill,
        addressPo,
        addressPs,
        addressDist,
      ].where((p) => p.trim().isNotEmpty).join(', ');

  /// সম্পাদনাযোগ্য ফিল্ড বদলে নতুন কপি।
  /// স্তর ১: নাম/পিতা/মোবাইল/ঠিকানা/নম্বর/বছর।
  /// স্তর ২: className/forikNo/classLevel — বদলালে provider ফাইল-মুভ চালায়।
  Student copyWith({
    String? stuName,
    String? fatherName,
    String? guardianMobile,
    String? dakhilaYear,
    String? marhala,
    String? examYear,
    String? avgMonth,
    String? avg1st,
    String? avg2nd,
    String? avgFinal,
    String? addressVill,
    String? addressPo,
    String? addressPs,
    String? addressDist,
    String? className,
    String? forikNo,
    String? classLevel,
    String? motherName,
    String? birthDate,
    String? birthCertNo,
    String? stuNameEn,
    String? stuNameAr,
    String? fatherNameEn,
    String? fatherNameAr,
    String? motherNameEn,
    String? motherNameAr,
  }) {
    return Student(
      dakhila: dakhila,
      stuName: stuName ?? this.stuName,
      className: className ?? this.className,
      forikNo: forikNo ?? this.forikNo,
      fatherName: fatherName ?? this.fatherName,
      guardianMobile: guardianMobile ?? this.guardianMobile,
      dakhilaYear: dakhilaYear ?? this.dakhilaYear,
      classLevel: classLevel ?? this.classLevel,
      marhala: marhala ?? this.marhala,
      examYear: examYear ?? this.examYear,
      motherName: motherName ?? this.motherName,
      birthDate: birthDate ?? this.birthDate,
      birthCertNo: birthCertNo ?? this.birthCertNo,
      avgMonth: avgMonth ?? this.avgMonth,
      avg1st: avg1st ?? this.avg1st,
      avg2nd: avg2nd ?? this.avg2nd,
      avgFinal: avgFinal ?? this.avgFinal,
      addressVill: addressVill ?? this.addressVill,
      addressPo: addressPo ?? this.addressPo,
      addressPs: addressPs ?? this.addressPs,
      addressDist: addressDist ?? this.addressDist,
      stuNameEn: stuNameEn ?? this.stuNameEn,
      stuNameAr: stuNameAr ?? this.stuNameAr,
      fatherNameEn: fatherNameEn ?? this.fatherNameEn,
      fatherNameAr: fatherNameAr ?? this.fatherNameAr,
      motherNameEn: motherNameEn ?? this.motherNameEn,
      motherNameAr: motherNameAr ?? this.motherNameAr,
      imagePath: imagePath,
      isCaptured: isCaptured,
      totalDocs: totalDocs,
    );
  }

  /// JSON/Excel মান → পরিষ্কার স্ট্রিং। নতুন Data_basic.json-এ FORIK_NO/
  /// AVG_NUM_* কলাম float (1.0, 81.0) হিসেবে আসে — পূর্ণসংখ্যা হলে
  /// দশমিক-শূন্য বাদ দিয়ে লেখা হয় (1.0 → '1'), নইলে যথারীতি ('87.63')।
  static String _toStr(dynamic v) {
    if (v == null) return '';
    if (v is num) {
      return v % 1 == 0 ? v.toInt().toString() : v.toString();
    }
    return v.toString().trim();
  }

  factory Student.fromJson(Map<String, dynamic> j) {
    return Student(
      dakhila: _toStr(j['DAKHILA']),
      stuName: _toStr(j['STU_NAME']),
      className: _toStr(j['CLASS_NAME']),
      forikNo: _toStr(j['FORIK_NO']),
      fatherName: _toStr(j['FATHER_NAME']),
      guardianMobile:
          _toStr(j['GAR_MOB_NO'] ?? j['GUARDIAN_MOBILE'] ?? j['MOBILE']),
      dakhilaYear: _toStr(j['DAKHILA_YEAR']).isEmpty
          ? '${DateTime.now().year}'
          : _toStr(j['DAKHILA_YEAR']),
      classLevel: _toStr(j['CLASS_LEVEL']),
      marhala: _toStr(j['MARHALA']),
      examYear: _toStr(j['EXAM_YEAR']),
      motherName: _toStr(j['MOTHER_NAME']),
      birthDate: _toStr(j['BIRTH_DATE'] ?? j['DOB']),
      birthCertNo: _toStr(j['BIRTH_CERTIFICATE_NO'] ?? j['ID_BIRTH_NO']),
      avgMonth: _toStr(j['AVG_NUM_MONTH']),
      avg1st: _toStr(j['AVG_NUM_1ST']),
      avg2nd: _toStr(j['AVG_NUM_2ND']),
      avgFinal: _toStr(j['AVG_NUM_FINAL']),
      addressVill: _toStr(j['PAR_ADD_VILL']),
      addressPo: _toStr(j['PAR_ADD_PO']),
      addressPs: _toStr(j['PAR_ADD_PS']),
      addressDist: _toStr(j['PAR_ADD_DIST']),
      // বান্ডেল JSON-এ নেই — ভবিষ্যৎ Excel-ইমপোর্টের জন্য snake_case কী
      stuNameEn: _toStr(j['stu_name_en']),
      stuNameAr: _toStr(j['stu_name_ar']),
      fatherNameEn: _toStr(j['father_name_en']),
      fatherNameAr: _toStr(j['father_name_ar']),
      motherNameEn: _toStr(j['mother_name_en']),
      motherNameAr: _toStr(j['mother_name_ar']),
      imagePath: j['image_path'],
      isCaptured: j['is_captured'] ?? 0,
      totalDocs: j['total_docs'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'dakhila': dakhila,
      'stu_name': stuName,
      'class_name': className,
      'forik_no': forikNo,
      'father_name': fatherName,
      'guardian_mobile': guardianMobile,
      'dakhila_year': dakhilaYear,
      'class_level': classLevel,
      'marhala': marhala,
      'exam_year': examYear,
      'mother_name': motherName,
      'birth_date': birthDate,
      'birth_certificate_no': birthCertNo,
      'avg_num_month': avgMonth,
      'avg_num_1st': avg1st,
      'avg_num_2nd': avg2nd,
      'avg_num_final': avgFinal,
      'address_vill': addressVill,
      'address_po': addressPo,
      'address_ps': addressPs,
      'address_dist': addressDist,
      'stu_name_en': stuNameEn,
      'stu_name_ar': stuNameAr,
      'father_name_en': fatherNameEn,
      'father_name_ar': fatherNameAr,
      'mother_name_en': motherNameEn,
      'mother_name_ar': motherNameAr,
      'image_path': imagePath,
      'is_captured': isCaptured,
      'total_docs': totalDocs,
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
