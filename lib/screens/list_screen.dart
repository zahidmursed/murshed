import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/student_provider.dart';
import 'camera_screen.dart';
import 'export_screen.dart';
import 'gallery_screen.dart';
import 'image_viewer_screen.dart';
import 'settings_screen.dart';

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
        title: const Text('Dakhila Camera'),
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
                  return ListTile(
                    leading: captured
                        ? CircleAvatar(
                            backgroundImage: FileImage(File(s.imagePath!)),
                            onBackgroundImageError: (_, __) {},
                            backgroundColor: Colors.grey,
                          )
                        : const CircleAvatar(
                            backgroundColor: Colors.grey,
                            child: Icon(Icons.person, color: Colors.white),
                          ),
                    title: Text('${s.dakhila} - ${s.stuName}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                        '${s.className} | ফরিক ${s.forikNo} | ${s.fatherName}'),
                    onTap: () {
                      if (captured) {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => ImageViewerScreen(student: s)));
                      } else {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => CameraScreen(student: s)));
                      }
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

  Widget _stat(String label, String value, {Color? color}) {
    return Column(children: [
      Text(value,
          style: TextStyle(
              fontSize: 22, fontWeight: FontWeight.bold, color: color)),
      Text(label)
    ]);
  }
}
