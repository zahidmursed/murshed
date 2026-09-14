import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/student_provider.dart';
import 'camera_screen.dart';

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
                  ]))
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
                        initialValue: provider.selectedForik.isEmpty
                            ? null
                            : provider.selectedForik,
                        hint: const Text('ফরিক ফিল্টার'),
                        items: List.generate(
                            12,
                            (i) => DropdownMenuItem(
                                value: '${i + 1}',
                                child: Text('ফরিক ${i + 1}'))),
                        onChanged: (v) {
                          if (v != null) provider.setForik(v);
                        },
                        decoration: const InputDecoration(
                            border: OutlineInputBorder(), isDense: true),
                      )),
                      const SizedBox(width: 8),
                      ElevatedButton(
                          onPressed: () => provider.setForik(''),
                          child: const Text('All')),
                      const SizedBox(width: 8),
                      Row(children: [
                        const Text('Serial'),
                        Switch(
                            value: provider.isSerialMode,
                            onChanged: (v) => provider.toggleSerial(v))
                      ])
                    ],
                  )
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                itemCount: provider.students.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, idx) {
                  final s = provider.students[idx];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                          s.isCaptured == 1 ? Colors.green : Colors.grey,
                      child: Icon(
                          s.isCaptured == 1 ? Icons.check : Icons.person,
                          color: Colors.white),
                    ),
                    title: Text('${s.dakhila} - ${s.stuName}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                        '${s.className} | ফরিক ${s.forikNo} | ${s.fatherName}'),
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
