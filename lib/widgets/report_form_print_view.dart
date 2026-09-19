import 'dart:io';

import 'package:flutter/material.dart';

import '../models/document.dart';

/// প্রিন্ট-বান্ধব রিপোর্ট ফরম (PDF-এর জন্য) — সাদা ব্যাকগ্রাউন্ড, কোনো
/// ইন্টারেক্টিভ এলিমেন্ট নেই; তিন লিপিতে (বাংলা/ইংরেজি/আরবী) নামসহ
/// সম্পূর্ণ তথ্য + ডকুমেন্ট-স্ট্যাটাস + স্বাক্ষর ঘর।
class ReportFormPrintView extends StatelessWidget {
  final StudentWithDocs swd;
  final String institutionName;
  final String? institutionLogoPath;
  final String teacherName;
  final String teacherMobile;

  const ReportFormPrintView({
    super.key,
    required this.swd,
    required this.institutionName,
    this.institutionLogoPath,
    required this.teacherName,
    required this.teacherMobile,
  });

  @override
  Widget build(BuildContext context) {
    final s = swd.student;
    final logo = institutionLogoPath;
    final hasLogo = logo != null && File(logo).existsSync();
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasLogo || institutionName.isNotEmpty) ...[
            if (hasLogo) ...[
              Center(
                child: Image.file(File(logo), height: 56, fit: BoxFit.contain),
              ),
              const SizedBox(height: 4),
            ],
            if (institutionName.isNotEmpty)
              Center(
                child: Text(institutionName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            const SizedBox(height: 6),
          ],
          _header(swd),
          const Divider(height: 20),
          _section('শিক্ষার্থীর তথ্য', [
            ..._nameRows('নাম', (s.stuName, s.stuNameEn, s.stuNameAr)),
            ..._nameRows(
                'পিতা', (s.fatherName, s.fatherNameEn, s.fatherNameAr)),
            ..._nameRows(
                'মাতা', (s.motherName, s.motherNameEn, s.motherNameAr)),
            _row('দাখিলা', s.dakhila),
            _row('ক্লাস', _levelSuffix(swd)),
            _row('ফরিক', s.forikNo),
            _row('মারহালা', s.marhala),
            _row('পরীক্ষার বছর', s.examYear),
            _row('দাখিলা বছর', s.dakhilaYear),
            _row('জন্ম তারিখ', s.birthDate),
            _row('জন্মসনদ নম্বর', s.birthCertNo),
            _row('ঠিকানা', s.addressFull),
            _row('অভিভাবকের মোবাইল', s.guardianMobile),
          ]),
          if (teacherName.isNotEmpty || teacherMobile.isNotEmpty)
            _section('শিক্ষক', [
              _row('নাম', teacherName),
              _row('মোবাইল', teacherMobile),
            ]),
          _section('ডকুমেন্ট স্ট্যাটাস', [
            _docRow('ছবি', DocType.PHOTO),
            _docRow('জন্মসনদ', DocType.BIRTH),
            _docRow('ফরম', DocType.FORM),
          ]),
          _section('পরীক্ষার নম্বর', [
            _row('মাসিক পরীক্ষা', s.avgMonth),
            _row('প্রথম সাময়িক', s.avg1st),
            _row('দ্বিতীয় সাময়িক', s.avg2nd),
            _row('বার্ষিক পরীক্ষা', s.avgFinal),
          ]),
          const SizedBox(height: 36),
          _signatureRow(),
        ],
      ),
    );
  }

  String _levelSuffix(StudentWithDocs swd) {
    final s = swd.student;
    final level = s.classLevel.isEmpty ? '' : ' (লেভেল ${s.classLevel})';
    return '${s.className}$level';
  }

  Widget _header(StudentWithDocs swd) {
    final s = swd.student;
    final photo = s.imagePath;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: 84,
            height: 104,
            child: (photo != null && File(photo).existsSync())
                ? Image.file(File(photo),
                    fit: BoxFit.cover,
                    cacheWidth: 300,
                    errorBuilder: (_, __, ___) => _placeholder())
                : _placeholder(),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (s.stuNameAr.isNotEmpty) ...[
                Directionality(
                  textDirection: TextDirection.rtl,
                  child: Text(s.stuNameAr,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14)),
                ),
                const SizedBox(height: 2),
              ],
              Text(s.stuName,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              if (s.stuNameEn.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(s.stuNameEn,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(fontSize: 11, color: Colors.black54)),
              ],
              const SizedBox(height: 4),
              Text('দাখিলা: ${s.dakhila}',
                  style: const TextStyle(color: Colors.black54, fontSize: 12)),
              Text(
                  '${s.className} | ফরিক ${s.forikNo} | ${swd.completedCount}/3 ডক',
                  style: const TextStyle(color: Colors.black54, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }

  static Widget _placeholder() => const ColoredBox(
        color: Colors.grey,
        child: Icon(Icons.person, color: Colors.white, size: 40),
      );

  Widget _section(String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          const Divider(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 110,
              child: Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 12))),
          Expanded(
            child: Text(value.trim().isEmpty ? '—' : value.trim(),
                style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  List<Widget> _nameRows(String label, (String, String, String) names) => [
        _row(label, names.$1),
        if (names.$2.isNotEmpty) _row('$label (ইংরেজি)', names.$2),
        if (names.$3.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                    width: 110,
                    child: Text('$label (আরবী)',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 12))),
                Expanded(
                  child: Directionality(
                    textDirection: TextDirection.rtl,
                    child:
                        Text(names.$3, style: const TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ),
      ];

  Widget _docRow(String label, DocType type) {
    final done = swd.docs[type] != null;
    return _row(label, done ? '✓ জমা আছে' : '✗ বাকি');
  }

  Widget _signatureRow() {
    Widget sig(String label) => Expanded(
          child: Column(
            children: [
              const SizedBox(height: 32),
              const Divider(color: Colors.black54),
              Text(label, style: const TextStyle(fontSize: 11)),
            ],
          ),
        );
    return Row(
      children: [
        sig('অভিভাবকের স্বাক্ষর'),
        const SizedBox(width: 24),
        sig('শিক্ষকের স্বাক্ষর'),
      ],
    );
  }
}