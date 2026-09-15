import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/document.dart';
import '../models/student.dart';
import '../providers/student_provider.dart';
import '../utils/contact_helper.dart';
import '../utils/gallery_saver.dart';

/// ছাত্র-প্রতি "রিপোর্ট ফরম" ভিউ — লোড করা সব ডেটা এক নজরে:
/// শিক্ষার্থীর তথ্য + ডকুমেন্ট স্ট্যাটাস + অভিভাবক যোগাযোগ (কল/হোয়াটসঅ্যাপ)
/// + স্বাক্ষর ঘর। টেক্সট আকারে শেয়ারও করা যায় (WhatsApp/SMS)।
class StudentReportScreen extends StatelessWidget {
  final Student student;
  const StudentReportScreen({super.key, required this.student});

  String _yn(StudentWithDocs swd, DocType type) => swd.hasDoc(type) ? '✓' : '✗';

  Future<void> _shareAsText(
      BuildContext context, StudentProvider provider) async {
    final swd = provider.withDocs(student);
    final mobile = student.guardianMobile.trim();
    final level =
        student.classLevel.isEmpty ? '' : ' (লেভেল ${student.classLevel})';
    final inst = provider.institutionName;
    final buf = StringBuffer()
      ..writeln(inst.isEmpty
          ? '📋 শিক্ষার্থী রিপোর্ট ফরম'
          : '📋 $inst — শিক্ষার্থী রিপোর্ট ফরম')
      ..writeln('━━━━━━━━━━━━━━━━━')
      ..writeln('দাখিলা: ${student.dakhila}')
      ..writeln('নাম: ${student.stuName}')
      ..writeln('পিতা: ${student.fatherName}')
      ..writeln('ক্লাস: ${student.className}$level')
      ..writeln('ফরিক: ${student.forikNo}')
      ..writeln('মারহালা: ${student.marhala.isEmpty ? '—' : student.marhala}')
      ..writeln(
          'পরীক্ষার বছর: ${student.examYear.isEmpty ? '—' : student.examYear}')
      ..writeln('দাখিলা বছর: ${student.dakhilaYear}')
      ..writeln('মোবাইল: ${mobile.isEmpty ? '—' : mobile}')
      ..writeln('ডকুমেন্ট: ছবি ${_yn(swd, DocType.PHOTO)} | '
          'জন্মসনদ ${_yn(swd, DocType.BIRTH)} | ফরম ${_yn(swd, DocType.FORM)} '
          '(${swd.completedCount}/3)');
    final messenger = ScaffoldMessenger.of(context);
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
    final swd = provider.withDocs(student);
    final mobile = student.guardianMobile.trim();
    return Scaffold(
      appBar: AppBar(
        title: Text('রিপোর্ট ফরম: ${student.dakhila}'),
        backgroundColor: Colors.teal,
        actions: [
          IconButton(
            tooltip: 'টেক্সট আকারে শেয়ার (WhatsApp/SMS)',
            icon: const Icon(Icons.share),
            onPressed: () => _shareAsText(context, provider),
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
          _detailsCard(context, mobile),
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
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _headerCard(StudentWithDocs swd) {
    final photo = student.imagePath;
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
                  Text(student.stuName,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('দাখিলা: ${student.dakhila}',
                      style: const TextStyle(color: Colors.black54)),
                  Text(
                      '${student.className} | ফরিক ${student.forikNo} | '
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

  Widget _detailsCard(BuildContext context, String mobile) {
    final level =
        student.classLevel.isEmpty ? '' : ' (লেভেল ${student.classLevel})';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('শিক্ষার্থীর তথ্য',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const Divider(height: 16),
            _row('দাখিলা', student.dakhila),
            _row('নাম', student.stuName),
            _row('পিতা', student.fatherName),
            _row('ক্লাস', '${student.className}$level'),
            _row('ফরিক', student.forikNo),
            _row('মারহালা', student.marhala),
            _row('পরীক্ষার বছর', student.examYear),
            _row('দাখিলা বছর', student.dakhilaYear),
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
                        child: Text(mobile,
                            style: const TextStyle(fontSize: 13))),
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