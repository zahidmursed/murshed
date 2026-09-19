import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/document.dart';
import '../models/student.dart';
import '../providers/student_provider.dart';
import 'document_scanner_screen.dart';

/// ব্যাচ স্ক্যান — একই ধরনের ডকুমেন্ট (BIRTH/FORM) অনেক ছাত্রের জন্য
/// পরপর স্ক্যান করা। লিস্টে শুধু যাদের এই ডক এখনো নেই তারাই দেখায়;
/// স্ক্যান-সেভ হয়ে ফিরলে লিস্ট নিজেই ছোট হয়ে যায়।
class BatchScanScreen extends StatefulWidget {
  final DocType type;

  const BatchScanScreen({super.key, required this.type});

  @override
  State<BatchScanScreen> createState() => _BatchScanScreenState();
}

class _BatchScanScreenState extends State<BatchScanScreen> {
  final Set<String> _scannedThisSession = {};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('ব্যাচ স্ক্যান: ${widget.type.label}'),
        backgroundColor: Colors.teal,
      ),
      body: Consumer<StudentProvider>(
        builder: (context, provider, _) {
          final pending = provider.students
              .where((s) => provider.docOf(s.dakhila, widget.type) == null)
              .toList();
          return Column(
            children: [
              Container(
                width: double.infinity,
                color: Colors.teal.shade50,
                padding: const EdgeInsets.all(10),
                child: Text(
                  'বাকি: ${pending.length} • এই সেশনে স্ক্যান: '
                  '${_scannedThisSession.length}\n'
                  'ছাত্রে ট্যাপ করুন → স্ক্যান হবে → ফিরে এসে পরেরটা করুন। '
                  'হোম স্ক্রিনের ক্লাস/ফরিক ফিল্টার এখানেও প্রযোজ্য।',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              Expanded(
                child: pending.isEmpty
                    ? const Center(
                        child: Text(
                            'এই ধরনের সব ছাত্রের ডকুমেন্ট আছে ✓',
                            textAlign: TextAlign.center),
                      )
                    : ListView.separated(
                        itemCount: pending.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final s = pending[i];
                          final fresh =
                              _scannedThisSession.contains(s.dakhila);
                          return ListTile(
                            leading: Icon(
                              Icons.description,
                              color: fresh ? Colors.green : Colors.deepOrange,
                            ),
                            title: Text(
                                '${s.dakhila} - ${s.stuName}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            subtitle: Text('${s.className} | ফরিক ${s.forikNo}'),
                            trailing: fresh
                                ? const Icon(Icons.check_circle,
                                    color: Colors.green)
                                : const Icon(Icons.chevron_right),
                            onTap: () => _runBatch(context, provider, s),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// ব্যাচ চক্র: স্ক্যান → সেভ → স্বয়ংক্রিয়ভাবে পরের "বাকি" ছাত্রের
  /// স্ক্যান-স্ক্রিন। ইউজার ব্যাক করলে (result != true) চক্র থামে —
  /// ফাঁদে আটকায় না; স্কোপ শেষ হলে উদযাপন-বার্তা।
  Future<void> _runBatch(
      BuildContext context, StudentProvider provider, Student first) async {
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    Student? current = first;
    while (current != null) {
      final s = current;
      final saved = await nav.push(MaterialPageRoute(
          builder: (_) => DocumentScannerScreen(student: s, type: widget.type)));
      if (!mounted) return;
      if (saved != true) break; // ব্যাক/বাতিল — ইউজার বেরিয়ে যেতে চায়
      if (provider.docOf(s.dakhila, widget.type) == null) break; // সেভ হয়নি
      setState(() => _scannedThisSession.add(s.dakhila));

      final pending = provider.students
          .where((st) => provider.docOf(st.dakhila, widget.type) == null)
          .toList();
      if (pending.isEmpty) {
        messenger.showSnackBar(const SnackBar(
            content: Text('🎉 এই স্কোপে সব ডকুমেন্ট সম্পন্ন!')));
        break;
      }
      current = pending.first; // তালিকার ক্রমেই পরের "বাকি"
    }
  }
}