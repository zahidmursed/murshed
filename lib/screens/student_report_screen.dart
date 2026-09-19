import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/document.dart';
import '../models/student.dart';
import '../providers/case_notes_provider.dart';
import '../providers/student_provider.dart';
import '../providers/teacher_provider.dart';
import '../utils/case_notes_guard.dart';
import '../utils/contact_helper.dart';
import '../utils/gallery_saver.dart';
import '../utils/report_pdf.dart';
import 'case_notes_screen.dart';
import 'student_edit_screen.dart';

/// ছাত্র-প্রতি "রিপোর্ট ফরম" ভিউ — লোড করা সব ডেটা এক নজরে:
/// শিক্ষার্থীর তথ্য + ডকুমেন্ট স্ট্যাটাস + অভিভাবক যোগাযোগ (কল/হোয়াটসঅ্যাপ)
/// + স্বাক্ষর ঘর। টেক্সট আকারে শেয়ারও করা যায় (WhatsApp/SMS)।
class StudentReportScreen extends StatelessWidget {
  final Student student;
  const StudentReportScreen({super.key, required this.student});

  String _yn(StudentWithDocs swd, DocType type) => swd.hasDoc(type) ? '✓' : '✗';

  String _d(String v) => v.trim().isEmpty ? '—' : v.trim();

  /// শেয়ার-টেক্সটের নাম-লাইন: বাংলা | ইংরেজি | আরবী (যেগুলো সেট আছে)।
  String _multiLangLine(
      String label, String bn, String en, String ar) {
    final parts = <String>[
      _d(bn),
      if (en.trim().isNotEmpty) en.trim(),
      if (ar.trim().isNotEmpty) ar.trim(),
    ];
    return '$label: ${parts.join(' | ')}';
  }

  Future<void> _shareAsText(
      BuildContext context, StudentProvider provider, Student s) async {
    final messenger =
        ScaffoldMessenger.of(context); // async gap-এর আগে ক্যাপচার
    final swd = provider.withDocs(s);
    final mobile = s.guardianMobile.trim();
    final level = s.classLevel.isEmpty ? '' : ' (লেভেল ${s.classLevel})';
    final inst = provider.institutionName;
    final tProv = context.read<TeacherProvider>();
    await tProv.ensureLoaded();
    final teacher = tProv.find(s.className, s.forikNo);
    final buf = StringBuffer()
      ..writeln(inst.isEmpty
          ? '📋 শিক্ষার্থী রিপোর্ট ফরম'
          : '📋 $inst — শিক্ষার্থী রিপোর্ট ফরম')
      ..writeln('━━━━━━━━━━━━━━━━━')
      ..writeln('দাখিলা: ${s.dakhila}')
      ..writeln(_multiLangLine('নাম', s.stuName, s.stuNameEn, s.stuNameAr))
      ..writeln(_multiLangLine('পিতা', s.fatherName, s.fatherNameEn, s.fatherNameAr))
      ..writeln(_multiLangLine('মাতা', s.motherName, s.motherNameEn, s.motherNameAr))
      ..writeln('ক্লাস: ${s.className}$level')
      ..writeln('ফরিক: ${s.forikNo}')
      ..writeln('মারহালা: ${_d(s.marhala)}')
      ..writeln('পরীক্ষার বছর: ${_d(s.examYear)}')
      ..writeln('দাখিলা বছর: ${s.dakhilaYear}')
      ..writeln('জন্ম তারিখ: ${_d(s.birthDate)} | '
          'জন্মসনদ: ${_d(s.birthCertNo)}')
      ..writeln('মোবাইল: ${_d(mobile)}')
      ..writeln('ঠিকানা: ${_d(s.addressFull)}')
      ..writeln('নম্বর — মাসিক: ${_d(s.avgMonth)} | '
          'প্রথম সাময়িক: ${_d(s.avg1st)} | '
          'দ্বিতীয় সাময়িক: ${_d(s.avg2nd)} | '
          'বার্ষিক: ${_d(s.avgFinal)}')
      ..writeln(teacher == null
          ? 'শিক্ষক: —'
          : 'শিক্ষক: ${teacher.displayName}'
              '${teacher.mobile.isEmpty ? '' : ' (${teacher.mobile})'}')
      ..writeln('ডকুমেন্ট: ছবি ${_yn(swd, DocType.PHOTO)} | '
          'জন্মসনদ ${_yn(swd, DocType.BIRTH)} | ফরম ${_yn(swd, DocType.FORM)} '
          '(${swd.completedCount}/3)');
    final ok = await GallerySaver.shareText(text: buf.toString());
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('শেয়ার করা যায়নি')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StudentProvider>();
    // সম্পাদনার পরে সদ্য-সংরক্ষিত মান দেখাতে মাস্টার তালিকা থেকে হালনাগাদ কপি নেয়।
    final current = provider.findStudent(student.dakhila) ?? student;
    final swd = provider.withDocs(current);
    final mobile = current.guardianMobile.trim();
    return Scaffold(
      appBar: AppBar(
        title: Text('রিপোর্ট ফরম: ${current.dakhila}'),
        backgroundColor: Colors.teal,
        actions: [
          IconButton(
            tooltip: 'তথ্য সম্পাদনা',
            icon: const Icon(Icons.edit),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => StudentEditScreen(student: current)),
            ),
          ),
          IconButton(
            tooltip: 'রিপোর্ট ফরম PDF (প্রিন্ট/শেয়ার)',
            icon: const Icon(Icons.picture_as_pdf),
            onPressed: () => _exportReportPdf(context, current, swd),
          ),
          IconButton(
            tooltip: 'টেক্সট আকারে শেয়ার (WhatsApp/SMS)',
            icon: const Icon(Icons.share),
            onPressed: () => _shareAsText(context, provider, current),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _institutionHeader(provider),
          const SizedBox(height: 12),
          _headerCard(swd),
          const SizedBox(height: 12),
          _detailsCard(context, current, mobile),
          const SizedBox(height: 12),
          _teacherCard(context, current),
          const SizedBox(height: 12),
          _caseNotesCard(context, current),
          const SizedBox(height: 12),
          _examCard(current),
          const SizedBox(height: 12),
          _docsCard(swd),
          const SizedBox(height: 12),
          _signatureCard(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// রিপোর্ট ফরমের হেডার — প্রতিষ্ঠানের লোগো/নাম (সেট করা থাকলে)।
  Widget _institutionHeader(StudentProvider provider) {
    final logo = provider.institutionLogoPath;
    final hasLogo = logo != null && File(logo).existsSync();
    if (provider.institutionName.isEmpty && !hasLogo) {
      return const SizedBox.shrink();
    }
    return Column(
      children: [
        if (hasLogo) ...[
          Center(
            child: Image.file(File(logo), height: 64, fit: BoxFit.contain),
          ),
          const SizedBox(height: 6),
        ],
        if (provider.institutionName.isNotEmpty)
          Text(provider.institutionName,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _headerCard(StudentWithDocs swd) {
    // imagePath (legacy ফিল্ড) না থাকলে/ফাইল হারালে PHOTO ডকুমেন্টের
    // পাথ থেকে দেখানোর ফলব্যাক — documents টেবিলই v2-এর মূল সত্য।
    var photo = swd.student.imagePath;
    if (photo == null || !File(photo).existsSync()) {
      final docPhoto = swd.docs[DocType.PHOTO]?.filePath;
      if (docPhoto != null && File(docPhoto).existsSync()) photo = docPhoto;
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 84,
                height: 104,
                child: (photo != null && File(photo).existsSync())
                    ? Image.file(File(photo),
                        fit: BoxFit.cover, cacheWidth: 300)
                    : const ColoredBox(
                        color: Colors.grey,
                        child:
                            Icon(Icons.person, color: Colors.white, size: 40),
                      ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // আরবী নাম (সেট থাকলে) — ক্লাসিক ফরমে উপরে থাকে
                  if (swd.student.stuNameAr.isNotEmpty) ...[
                    Directionality(
                      textDirection: TextDirection.rtl,
                      child: Text(swd.student.stuNameAr,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 15)),
                    ),
                    const SizedBox(height: 2),
                  ],
                  Text(swd.student.stuName,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                  if (swd.student.stuNameEn.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(swd.student.stuNameEn,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black54)),
                  ],
                  const SizedBox(height: 4),
                  Text('দাখিলা: ${swd.student.dakhila}',
                      style: const TextStyle(color: Colors.black54)),
                  Text(
                      '${swd.student.className} | ফরিক ${swd.student.forikNo} | '
                      '${swd.completedCount}/3 ডক',
                      style: const TextStyle(color: Colors.black54)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 120,
              child: Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13))),
          Expanded(
              child: Text(value.isEmpty ? '—' : value,
                  style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  /// নাম-সারি: বাংলা + (সেট থাকলে) ইংরেজি ও আরবী — প্রতিটি আলাদা লাইনে।
  List<Widget> _nameRows(String label, (String, String, String) names) => [
        _row(label, names.$1),
        if (names.$2.isNotEmpty) _row('$label (ইংরেজি)', names.$2),
        if (names.$3.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                    width: 120,
                    child: Text('$label (আরবী)',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13))),
                Expanded(
                  child: Directionality(
                    textDirection: TextDirection.rtl,
                    child: Text(names.$3, style: const TextStyle(fontSize: 13)),
                  ),
                ),
              ],
            ),
          ),
      ];

  Widget _detailsCard(BuildContext context, Student s, String mobile) {
    final level = s.classLevel.isEmpty ? '' : ' (লেভেল ${s.classLevel})';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('শিক্ষার্থীর তথ্য',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const Divider(height: 16),
            _row('দাখিলা', s.dakhila),
            ..._nameRows('নাম', (s.stuName, s.stuNameEn, s.stuNameAr)),
            ..._nameRows('পিতা', (s.fatherName, s.fatherNameEn, s.fatherNameAr)),
            ..._nameRows('মাতা', (s.motherName, s.motherNameEn, s.motherNameAr)),
            _row('ক্লাস', '${s.className}$level'),
            _row('ফরিক', s.forikNo),
            _row('মারহালা', s.marhala),
            _row('পরীক্ষার বছর', s.examYear),
            _row('দাখিলা বছর', s.dakhilaYear),
            _row('জন্ম তারিখ', s.birthDate),
            _row('জন্মসনদ নম্বর', s.birthCertNo),
            _row('ঠিকানা', s.addressFull),
            if (mobile.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    const SizedBox(
                        width: 120,
                        child: Text('অভিভাবকের মোবাইল',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13))),
                    Expanded(
                        child:
                            Text(mobile, style: const TextStyle(fontSize: 13))),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'সাধারণ কল',
                      icon: const Icon(Icons.call, color: Colors.teal),
                      onPressed: () async {
                        final ok = await ContactHelper.openDialer(mobile);
                        if (context.mounted && !ok) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('ডায়ালার খোলা যায়নি')),
                          );
                        }
                      },
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'হোয়াটসঅ্যাপ (কল/মেসেজ)',
                      icon: const Icon(Icons.chat, color: Colors.green),
                      onPressed: () async {
                        final intl = ContactHelper.normalizeBdMobile(mobile);
                        final ok = intl == null
                            ? false
                            : await ContactHelper.openWhatsAppChat(intl);
                        if (context.mounted && !ok) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('হোয়াটসঅ্যাপ খোলা যায়নি')),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// দায়িত্বপ্রাপ্ত শিক্ষক — ছাত্রের ক্লাস+ফরিক মিলিয়ে (teachers DB টেবিল,
  /// Settings → "শিক্ষক তালিকা সম্পাদনা" থেকে)। না পাওয়া গেলে কার্ড লুকায়।
  Widget _teacherCard(BuildContext context, Student s) {
    final tProv = context.watch<TeacherProvider>();
    if (!tProv.loaded) {
      // প্রথম ব্যবহারে DB থেকে লোড — সম্পন্ন হলে notifyListeners-এ পুনর্বিল্ড হবে।
      tProv.ensureLoaded();
      return const SizedBox.shrink();
    }
    final teacher = tProv.find(s.className, s.forikNo);
    if (teacher == null) return const SizedBox.shrink();
    final digits = teacher.mobile;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('দায়িত্বপ্রাপ্ত শিক্ষক',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const Divider(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.school, size: 20, color: Colors.teal),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(teacher.displayName,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                      if (teacher.nameEn.isNotEmpty &&
                          teacher.nameEn != teacher.displayName)
                        Text(teacher.nameEn,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.black54)),
                      const SizedBox(height: 2),
                      Text('ক্লাস: ${s.className} · ফরিক: ${s.forikNo}',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black54)),
                    ],
                  ),
                ),
              ],
            ),
            if (digits.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    const SizedBox(
                        width: 120,
                        child: Text('মোবাইল',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13))),
                    Expanded(
                        child:
                            Text(digits, style: const TextStyle(fontSize: 13))),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'সাধারণ কল',
                      icon: const Icon(Icons.call, color: Colors.teal),
                      onPressed: () async {
                        final ok = await ContactHelper.openDialer(digits);
                        if (context.mounted && !ok) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('ডায়ালার খোলা যায়নি')),
                          );
                        }
                      },
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'হোয়াটসঅ্যাপ (কল/মেসেজ)',
                      icon: const Icon(Icons.chat, color: Colors.green),
                      onPressed: () async {
                        final intl = ContactHelper.normalizeBdMobile(digits);
                        final ok = intl == null
                            ? false
                            : await ContactHelper.openWhatsAppChat(intl);
                        if (context.mounted && !ok) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('হোয়াটসঅ্যাপ খোলা যায়নি')),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// কেস নোট — সংখ্যা দেখায়; ট্যাপ করলে PIN গার্ড → নোট স্ক্রিন।
  /// সংবেদনশীল তথ্য — শেয়ার টেক্সটে যায় না (নোট স্ক্রিন থেকে আলাদা শেয়ার)।
  Widget _caseNotesCard(BuildContext context, Student s) {
    final cProv = context.watch<CaseNotesProvider>();
    if (!cProv.loaded) {
      cProv.ensureLoaded();
      return const SizedBox.shrink();
    }
    final count = cProv.countFor(s.dakhila);
    return Card(
      child: ListTile(
        leading: const Icon(Icons.gavel, color: Colors.deepOrange),
        title: const Text('কেস নোট'),
        subtitle: Text(count == 0 ? 'কোনো নোট নেই' : '$count টি নোট সংরক্ষিত'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          final ok = await CaseNotesGuard.ensureUnlocked(context);
          if (!ok || !context.mounted) return;
          context.read<CaseNotesProvider>().ensureLoaded();
          if (!context.mounted) return;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  CaseNotesScreen(dakhila: s.dakhila, studentName: s.stuName),
            ),
          );
        },
      ),
    );
  }

  /// পূর্ণ রিপোর্ট ফরম PDF — উইজেট→ছবি→PDF পদ্ধতি (বাংলা যুক্তাক্ষর ও
  /// আরবী দুটোই Flutter-এর নিজস্ব টেক্সট-স্ট্যাক দিয়ে নিখুঁত শেপ হয়)।
  Future<void> _exportReportPdf(
      BuildContext context, Student current, StudentWithDocs swd) async {
    // প্রথম ফ্রেমেই context-নির্ভর সবকিছু ক্যাপচার (async gap-এর আগে)
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context, rootNavigator: true);
    final overlay = Overlay.of(context, rootOverlay: true);
    final provider = context.read<StudentProvider>();
    final tProv = context.read<TeacherProvider>();
    final institutionName = provider.institutionName;
    final logoPath = provider.institutionLogoPath;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Colors.teal),
                SizedBox(height: 12),
                Text('PDF তৈরি হচ্ছে...'),
              ],
            ),
          ),
        ),
      ),
    );
    try {
      await tProv.ensureLoaded();
      final teacher = tProv.find(current.className, current.forikNo);
      final path = await ReportPdf.export(
        overlay: overlay,
        swd: swd,
        institutionName: institutionName,
        institutionLogoPath: logoPath,
        teacherName: teacher?.displayName ?? '',
        teacherMobile: teacher?.mobile ?? '',
      );
      navigator.pop(); // প্রগ্রেস ডায়ালগ বন্ধ
      messenger.showSnackBar(SnackBar(content: Text('সেভ হয়েছে: $path')));
      await GallerySaver.shareFile(path: path, mime: 'application/pdf');
    } catch (e) {
      navigator.pop();
      debugPrint('Report PDF failed: $e');
      messenger.showSnackBar(SnackBar(content: Text('PDF তৈরি ব্যর্থ: $e')));
    }
  }

  /// রিপোর্ট ফরম: পরীক্ষার গড় নম্বর (মাসিক/প্রথম সাময়িক/দ্বিতীয় সাময়িক/বার্ষিক)।
  Widget _examCard(Student s) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('পরীক্ষার নম্বর',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const Divider(height: 16),
            _row('মাসিক পরীক্ষা', s.avgMonth),
            _row('প্রথম সাময়িক', s.avg1st),
            _row('দ্বিতীয় সাময়িক', s.avg2nd),
            _row('বার্ষিক পরীক্ষা', s.avgFinal),
          ],
        ),
      ),
    );
  }

  Widget _docsCard(StudentWithDocs swd) {
    Widget docRow(DocType type) {
      final doc = swd.docs[type];
      final done = doc != null;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(
              type == DocType.PHOTO ? Icons.photo_camera : Icons.description,
              size: 20,
              color: done ? Colors.teal : Colors.grey,
            ),
            const SizedBox(width: 8),
            Expanded(
                child: Text(type.label, style: const TextStyle(fontSize: 13))),
            Icon(
              done ? Icons.check_circle : Icons.cancel,
              size: 18,
              color: done ? Colors.green : Colors.redAccent,
            ),
            const SizedBox(width: 6),
            Text(done ? 'জমা আছে' : 'বাকি',
                style: TextStyle(
                    fontSize: 12,
                    color: done ? Colors.green.shade800 : Colors.redAccent)),
          ],
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('ডকুমেন্ট স্ট্যাটাস',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const Divider(height: 16),
            docRow(DocType.PHOTO),
            docRow(DocType.BIRTH),
            docRow(DocType.FORM),
          ],
        ),
      ),
    );
  }

  Widget _signatureCard() {
    Widget sig(String label) => Expanded(
          child: Column(
            children: [
              const SizedBox(height: 40),
              const Divider(color: Colors.black54),
              Text(label, style: const TextStyle(fontSize: 12)),
            ],
          ),
        );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            sig('অভিভাবকের স্বাক্ষর'),
            const SizedBox(width: 24),
            sig('শিক্ষকের স্বাক্ষর'),
          ],
        ),
      ),
    );
  }
}
