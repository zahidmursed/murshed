import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/case_note.dart';
import '../providers/case_notes_provider.dart';

/// ছাত্র-প্রতি কেস নোট — তালিকা + যোগ/সম্পাদনা/মুছে ফেলা।
/// প্রবেশের আগে PIN গার্ড (CaseNotesGuard) রিপোর্ট ফরম থেকেই সামলায়।
class CaseNotesScreen extends StatefulWidget {
  final String dakhila;
  final String studentName;

  const CaseNotesScreen({
    super.key,
    required this.dakhila,
    required this.studentName,
  });

  @override
  State<CaseNotesScreen> createState() => _CaseNotesScreenState();
}

class _CaseNotesScreenState extends State<CaseNotesScreen> {
  static const _categories = ['শৃঙ্খলা', 'অনুপস্থিতি', 'মামলা', 'অন্যান্য'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<CaseNotesProvider>().ensureLoaded();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cProv = context.watch<CaseNotesProvider>();
    final notes = cProv.notesFor(widget.dakhila);
    return Scaffold(
      appBar: AppBar(
        title: Text('কেস নোট: ${widget.studentName} (${widget.dakhila})'),
        backgroundColor: Colors.deepOrange,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEditDialog(),
        icon: const Icon(Icons.post_add),
        label: const Text('নতুন নোট'),
        backgroundColor: Colors.deepOrange,
      ),
      body: notes.isEmpty
          ? const Center(
              child: Text(
              'কোনো কেস নোট নেই\nনিচের "নতুন নোট" বাটনে যোগ করুন',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ))
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
              itemCount: notes.length,
              itemBuilder: (context, i) {
                final n = notes[i];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 4, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (n.category.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.deepOrange.shade100,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(n.category,
                                    style: const TextStyle(fontSize: 11)),
                              ),
                            const SizedBox(width: 8),
                            Text(n.noteDate,
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.black54)),
                            const Spacer(),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: 'সম্পাদনা',
                              icon: const Icon(Icons.edit,
                                  size: 20, color: Colors.teal),
                              onPressed: () => _showEditDialog(existing: n),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: 'মুছে ফেলুন',
                              icon: const Icon(Icons.delete_outline,
                                  size: 20, color: Colors.redAccent),
                              onPressed: () => _confirmDelete(n),
                            ),
                          ],
                        ),
                        if (n.title.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(n.title,
                                style: const TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w600)),
                          ),
                        Padding(
                          padding: const EdgeInsets.only(top: 4, bottom: 6),
                          child: Text(n.details,
                              style: const TextStyle(fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Future<void> _showEditDialog({CaseNote? existing}) {
    final now = DateTime.now();
    final initialDate = existing?.noteDate ??
        '${now.day.toString().padLeft(2, '0')}-'
            '${now.month.toString().padLeft(2, '0')}-'
            '${now.year}';
    final dateCtl = TextEditingController(text: initialDate);
    final titleCtl = TextEditingController(text: existing?.title ?? '');
    final detailsCtl = TextEditingController(text: existing?.details ?? '');
    var category = (existing?.category.isEmpty ?? true)
        ? _categories.first
        : existing!.category;

    Future<void> pickDate() async {
      final parts = dateCtl.text.split('-');
      DateTime initial = now;
      if (parts.length == 3) {
        final d = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        final y = int.tryParse(parts[2]);
        if (d != null && m != null && y != null) {
          initial = DateTime(y, m, d);
        }
      }
      final picked = await showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: DateTime(2000),
        lastDate: DateTime(now.year + 1),
      );
      if (picked != null) {
        dateCtl.text = '${picked.day.toString().padLeft(2, '0')}-'
            '${picked.month.toString().padLeft(2, '0')}-'
            '${picked.year}';
      }
    }

    return showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'নতুন কেস নোট' : 'নোট সম্পাদনা'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: dateCtl,
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: 'ঘটনার তারিখ *',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.calendar_month),
                      onPressed: pickDate,
                    ),
                  ),
                  onTap: pickDate,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _categories.contains(category)
                      ? category
                      : _categories.first,
                  decoration: const InputDecoration(
                    labelText: 'ধরন',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: _categories
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setDialogState(() => category = v);
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: titleCtl,
                  decoration: const InputDecoration(
                    labelText: 'শিরোনাম',
                    hintText: 'যেমন: ক্লাসে দেরিতে আসা',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: detailsCtl,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'বিস্তারিত *',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('বাতিল'),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.save),
              label: const Text('সংরক্ষণ'),
              onPressed: () => _saveNote(dialogContext, existing, dateCtl,
                  titleCtl, detailsCtl, category),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveNote(
    BuildContext dialogContext,
    CaseNote? existing,
    TextEditingController dateCtl,
    TextEditingController titleCtl,
    TextEditingController detailsCtl,
    String category,
  ) async {
    if (detailsCtl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('বিস্তারিত লিখুন')));
      return;
    }
    final nowIso = DateTime.now().toIso8601String();
    final ok = await dialogContext.read<CaseNotesProvider>().upsert(CaseNote(
          id: existing?.id,
          dakhila: widget.dakhila,
          noteDate: dateCtl.text.trim(),
          category: category,
          title: titleCtl.text.trim(),
          details: detailsCtl.text.trim(),
          createdAt: existing?.createdAt ?? nowIso,
          updatedAt: nowIso,
        ));
    if (!dialogContext.mounted) return;
    Navigator.pop(dialogContext);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ok ? '✅ নোট সংরক্ষিত' : 'সংরক্ষণ করা যায়নি')));
    }
  }

  void _confirmDelete(CaseNote n) {
    showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('নোট মুছে ফেলবেন?'),
        content: Text('${n.noteDate}${n.title.isEmpty ? '' : ' — ${n.title}'}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('না'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('হ্যাঁ, মুছুন'),
          ),
        ],
      ),
    ).then((ok) async {
      if (ok != true || !mounted) return;
      final done = await context.read<CaseNotesProvider>().delete(n.id!);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(done ? 'নোট মুছে ফেলা হয়েছে' : 'মুছে ফেলা যায়নি'),
      ));
    });
  }
}
