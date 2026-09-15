import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/document.dart';
import '../providers/student_provider.dart';
import '../utils/contact_helper.dart';
import 'batch_scan_screen.dart';
import 'camera_screen.dart';
import 'document_dashboard_screen.dart';
import 'export_screen.dart';
import 'gallery_screen.dart';
import 'settings_screen.dart';
import 'student_report_screen.dart';

class ListScreen extends StatefulWidget {
  const ListScreen({super.key});
  @override
  State<ListScreen> createState() => _ListScreenState();
}

class _ListScreenState extends State<ListScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    // async gap-এর আগেই provider capture — use_build_context_synchronously এড়াতে
    final provider = context.read<StudentProvider>();
    Future.microtask(provider.load);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Consumer<StudentProvider>(
          builder: (_, p, __) {
            final logo = p.institutionLogoPath;
            final hasLogo = logo != null && File(logo).existsSync();
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasLogo) ...[
                  Image.file(File(logo),
                      width: 30, height: 30, fit: BoxFit.contain),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    p.institutionName.isEmpty
                        ? 'Dakhila Camera'
                        : p.institutionName,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            );
          },
        ),
        backgroundColor: Colors.teal,
        actions: [
          Consumer<StudentProvider>(
              builder: (_, p, __) => Row(children: [
                    const Text('Passport'),
                    Switch(
                        value: p.isPassportMode,
                        onChanged: (v) => p.togglePassport(v)),
                  ])),
          IconButton(
            tooltip: 'ব্যাচ ডকুমেন্ট স্ক্যান',
            icon: const Icon(Icons.document_scanner),
            onPressed: _pickBatchType,
          ),
          IconButton(
            tooltip: 'তোলা ছবি',
            icon: const Icon(Icons.photo_library),
            onPressed: () {
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const GalleryScreen()));
            },
          ),
          IconButton(
            tooltip: 'এক্সপোর্ট',
            icon: const Icon(Icons.folder_zip),
            onPressed: () {
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ExportScreen()));
            },
          ),
          IconButton(
            tooltip: 'সেটিংস',
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()));
            },
          ),
        ],
      ),
      body: Consumer<StudentProvider>(builder: (context, provider, _) {
        if (provider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        return Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              color: Colors.teal.shade50,
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _stat('মোট', provider.total.toString()),
                      _stat('তোলা', provider.captured.toString(),
                          color: Colors.green),
                      _stat('বাকি', provider.remaining.toString(),
                          color: Colors.red),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (provider.selectedForik.isEmpty &&
                      provider.forikStats.isNotEmpty)
                    SizedBox(
                      height: 44,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: provider.forikStats.length,
                        itemBuilder: (context, i) {
                          final st = provider.forikStats[i];
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ActionChip(
                              label: Text(
                                  'ফরিক ${st.forik}: ${st.captured}/${st.total}'),
                              backgroundColor: st.isComplete
                                  ? Colors.green.shade100
                                  : (st.captured > 0
                                      ? Colors.orange.shade100
                                      : null),
                              onPressed: () => provider.setForik(st.forik),
                            ),
                          );
                        },
                      ),
                    ),
                  TextField(
                    controller: _searchCtrl,
                    decoration: const InputDecoration(
                        hintText: 'দাখিলা বা নাম দিয়ে সার্চ...',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                        isDense: true),
                    onChanged: (v) => provider.search(v),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                          child: DropdownButtonFormField<String>(
                        initialValue: provider.selectedClass.isEmpty
                            ? null
                            : provider.selectedClass,
                        hint: const Text('ক্লাস'),
                        items: provider.classes
                            .map((c) =>
                                DropdownMenuItem(value: c, child: Text(c)))
                            .toList(),
                        onChanged: (v) => provider.setClass(v ?? ''),
                        decoration: const InputDecoration(
                            border: OutlineInputBorder(), isDense: true),
                      )),
                      const SizedBox(width: 8),
                      Expanded(
                          child: DropdownButtonFormField<String>(
                        initialValue: provider.selectedForik.isEmpty
                            ? null
                            : provider.selectedForik,
                        hint: const Text('ফরিক'),
                        items: provider.foriks
                            .map((f) => DropdownMenuItem(
                                value: f, child: Text('ফরিক $f')))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) provider.setForik(v);
                        },
                        decoration: const InputDecoration(
                            border: OutlineInputBorder(), isDense: true),
                      )),
                      const SizedBox(width: 8),
                      ElevatedButton(
                          onPressed: () => provider.resetFilters(),
                          child: const Text('All')),
                    ],
                  ),
                  Row(children: [
                    const Text('Serial'),
                    Switch(
                        value: provider.isSerialMode,
                        onChanged: (v) => provider.toggleSerial(v))
                  ])
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                itemCount: provider.students.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, idx) {
                  final s = provider.students[idx];
                  final captured = s.isCaptured == 1 && s.imagePath != null;
                  final withDocs = provider.withDocs(s);
                  return ListTile(
                    leading: captured
                        ? CircleAvatar(
                            // পারফরম্যান্স ফিক্স: থাম্বনেইলে পুরো রেজোলিউশন
                            // ডিকোড নয় — 128px-এ (বড় লিস্টে মেমোরি ও jank কমায়)
                            backgroundImage: ResizeImage(
                              FileImage(File(s.imagePath!)),
                              width: 128,
                            ),
                            onBackgroundImageError: (_, __) {},
                            backgroundColor: Colors.grey,
                          )
                        : const CircleAvatar(
                            backgroundColor: Colors.grey,
                            child: Icon(Icons.person, color: Colors.white),
                          ),
                    title: Text('${s.dakhila} - ${s.stuName} | ${s.fatherName}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${s.className} | ফরিক ${s.forikNo}'),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            for (final t in DocType.values)
                              Container(
                                width: 10,
                                height: 10,
                                margin: const EdgeInsets.only(right: 4),
                                decoration: BoxDecoration(
                                  color: withDocs.hasDoc(t)
                                      ? Colors.green
                                      : Colors.grey.shade400,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            const SizedBox(width: 2),
                            Text(
                              '${withDocs.completedCount}/3 ডক',
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.black54),
                            ),
                            const Spacer(),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints:
                                  const BoxConstraints(minWidth: 28),
                              tooltip: 'রিপোর্ট ফরম',
                              icon: const Icon(Icons.assignment,
                                  size: 18, color: Colors.teal),
                              onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          StudentReportScreen(student: s))),
                            ),
                          ],
                        ),
                        if (s.guardianMobile.trim().isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Row(children: [
                            const Icon(Icons.phone,
                                size: 12, color: Colors.black45),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text('মোবাইল: ${s.guardianMobile.trim()}',
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.black54)),
                            ),
                            _contactIcon(
                                context,
                                Icons.call,
                                'সাধারণ কল',
                                () => ContactHelper.openDialer(
                                    s.guardianMobile.trim())),
                            _contactIcon(
                                context,
                                Icons.chat,
                                'হোয়াটসঅ্যাপ (কল/মেসেজ)',
                                () async {
                                  final intl = ContactHelper.normalizeBdMobile(
                                      s.guardianMobile.trim());
                                  if (intl == null) return false;
                                  return ContactHelper.openWhatsAppChat(intl);
                                }),
                          ]),
                        ],
                      ],
                    ),
                    onTap: () {
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  DocumentDashboardScreen(student: s)));
                    },
                    trailing: IconButton(
                      icon: const Icon(Icons.camera_alt, color: Colors.teal),
                      onPressed: () {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => CameraScreen(student: s)));
                      },
                    ),
                  );
                },
              ),
            )
          ],
        );
      }),
    );
  }

  /// ব্যাচ স্ক্যান — ধরন (BIRTH/FORM) বাছাই করে ব্যাচ-স্ক্রিনে যায়।
  Future<void> _pickBatchType() async {
    final type = await showDialog<DocType>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ব্যাচ ডকুমেন্ট স্ক্যান'),
        content: const Text(
            'কোন ধরনের ডকুমেন্ট স্ক্যান করবেন?\n'
            'লিস্টে শুধু যাদের এই ডকুমেন্ট এখনো নেই তারাই দেখাবে।'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('বাতিল'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, DocType.BIRTH),
            child: const Text('জন্মসনদ'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, DocType.FORM),
            child: const Text('নিবন্ধন ফরম'),
          ),
        ],
      ),
    );
    if (type == null || !mounted) return;
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => BatchScanScreen(type: type)));
  }

  Widget _stat(String label, String value, {Color? color}) {
    return Column(children: [
      Text(value,
          style: TextStyle(
              fontSize: 22, fontWeight: FontWeight.bold, color: color)),
      Text(label)
    ]);
  }

  /// ছোট অ্যাকশন আইকন (কল/হোয়াটসঅ্যাপ) — ব্যর্থ হলে snackbar।
  Widget _contactIcon(
      BuildContext context, IconData icon, String tooltip,
      Future<bool> Function() open) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28),
      tooltip: tooltip,
      icon: Icon(icon, size: 18, color: Colors.teal),
      onPressed: () async {
        final ok = await open();
        if (context.mounted && !ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('অ্যাপটি খোলা যায়নি')),
          );
        }
      },
    );
  }
}
