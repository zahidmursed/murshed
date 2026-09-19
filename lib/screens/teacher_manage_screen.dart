import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/teacher.dart';
import '../providers/student_provider.dart';
import '../providers/teacher_provider.dart';
import '../services/teacher_directory.dart';

/// শিক্ষক-তালিকা ম্যানেজ স্ক্রিন (স্তর ৪) — অ্যাপের ভেতরেই শিক্ষক
/// যোগ/সম্পাদনা/মুছে ফেলা; DB-র `teachers` টেবিলে সংরক্ষিত।
/// রিপোর্ট ফরম স্বয়ংক্রিয়ভাবে হালনাগাদ শিক্ষক দেখায়।
class TeacherManageScreen extends StatefulWidget {
  const TeacherManageScreen({super.key});

  @override
  State<TeacherManageScreen> createState() => _TeacherManageScreenState();
}

class _TeacherManageScreenState extends State<TeacherManageScreen> {
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    // প্রথম খোলায় DB থেকে লোড (idempotent)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<TeacherProvider>().ensureLoaded();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tProv = context.watch<TeacherProvider>();
    final q = TeacherDirectory.normText(_search.text).toLowerCase();
    final all = tProv.teachers;
    final filtered = q.isEmpty
        ? all
        : all
            .where((t) =>
                t.className.toLowerCase().contains(q) ||
                t.nameBn.toLowerCase().contains(q) ||
                t.nameEn.toLowerCase().contains(q) ||
                t.mobile.contains(q))
            .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('শিক্ষক তালিকা'),
        backgroundColor: Colors.teal,
        actions: [
          IconButton(
            tooltip: 'বান্ডল এক্সেল থেকে পুনরুদ্ধার',
            icon: const Icon(Icons.restore),
            onPressed: () => _confirmRestore(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEditDialog(),
        icon: const Icon(Icons.person_add),
        label: const Text('নতুন শিক্ষক'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: 'ক্লাস/নাম/মোবাইল দিয়ে খুঁজুন',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                  tProv.loaded ? 'মোট এন্ট্রি: ${all.length}' : 'লোড হচ্ছে...',
                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
            ),
          ),
          Expanded(
            child: !tProv.loaded
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? const Center(
                        child: Text('কোনো শিক্ষক পাওয়া যায়নি',
                            style: TextStyle(color: Colors.black54)))
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 88),
                        itemCount: filtered.length,
                        itemBuilder: (context, i) {
                          final t = filtered[i];
                          return ListTile(
                            leading:
                                const Icon(Icons.school, color: Colors.teal),
                            title: Text(t.displayName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            subtitle: Text(
                              'ক্লাস: ${t.className}'
                              '${t.forik.isEmpty ? '' : ' · ফরিক: ${t.forik}'}'
                              '${t.mobile.isEmpty ? '' : '\nমোবাইল: ${t.mobile}'}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            isThreeLine: t.mobile.isNotEmpty,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'সম্পাদনা',
                                  icon: const Icon(Icons.edit,
                                      color: Colors.teal),
                                  onPressed: () => _showEditDialog(existing: t),
                                ),
                                IconButton(
                                  tooltip: 'মুছে ফেলুন',
                                  icon: const Icon(Icons.delete_outline,
                                      color: Colors.redAccent),
                                  onPressed: () => _confirmDelete(t),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(TeacherInfo t) {
    showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('শিক্ষক মুছে ফেলবেন?'),
        content: Text('${t.displayName}\nক্লাস: ${t.className}'
            '${t.forik.isEmpty ? '' : ' · ফরিক: ${t.forik}'}'),
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
      final tProv = context.read<TeacherProvider>();
      final done = await tProv.delete(t.className, t.forik);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(done ? 'শিক্ষক মুছে ফেলা হয়েছে' : 'মুছে ফেলা যায়নি'),
      ));
    });
  }

  void _confirmRestore() {
    showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('বান্ডল ডেটা পুনরুদ্ধার?'),
        content: const Text(
            'বর্তমান শিক্ষক-তালিকা মুছে অ্যাপের সাথে আসা এক্সেল থেকে '
            'নতুন করে ভরা হবে। আপনার করা পরিবর্তন হারাবে।'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('না'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('হ্যাঁ, পুনরুদ্ধার'),
          ),
        ],
      ),
    ).then((ok) async {
      if (ok != true || !mounted) return;
      final count = await context.read<TeacherProvider>().restoreSeed();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('✅ $count জন শিক্ষক পুনরুদ্ধার হয়েছে'),
      ));
    });
  }

  Future<void> _showEditDialog({TeacherInfo? existing}) {
    final classCtl = TextEditingController(text: existing?.className ?? '');
    final forikCtl = TextEditingController(text: existing?.forik ?? '');
    final bnCtl = TextEditingController(text: existing?.nameBn ?? '');
    final enCtl = TextEditingController(text: existing?.nameEn ?? '');
    final mobCtl = TextEditingController(text: existing?.mobile ?? '');

    String? validate() {
      if (TeacherDirectory.normText(classCtl.text).isEmpty) {
        return 'ক্লাসের নাম দিন (ছাত্রের ক্লাসের সাথে হুবহু মিলতে হবে)';
      }
      if (TeacherDirectory.normText(bnCtl.text).isEmpty &&
          TeacherDirectory.normText(enCtl.text).isEmpty) {
        return 'শিক্ষকের নাম (বাংলা বা ইংরেজি) দিন';
      }
      if (mobCtl.text.trim().isNotEmpty &&
          TeacherDirectory.normMobile(mobCtl.text).isEmpty) {
        return 'মোবাইল নম্বর সঠিক নয়';
      }
      return null;
    }

    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(existing == null ? 'নতুন শিক্ষক' : 'শিক্ষক সম্পাদনা'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: classCtl,
                decoration: InputDecoration(
                  labelText: 'ক্লাসের নাম *',
                  hintText: 'যেমন: হিফয সবকী',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: IconButton(
                    tooltip: 'ক্লাস-তালিকা থেকে বাছুন',
                    icon: const Icon(Icons.arrow_drop_down),
                    onPressed: () async {
                      final classes =
                          dialogContext.read<StudentProvider>().classes;
                      final picked = await showModalBottomSheet<String>(
                        context: dialogContext,
                        builder: (_) => SafeArea(
                          child: classes.isEmpty
                              ? const Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Text('ক্লাস-তালিকা খালি'),
                                )
                              : ListView(
                                  shrinkWrap: true,
                                  children: classes
                                      .map((c) => ListTile(
                                            title: Text(c),
                                            onTap: () =>
                                                Navigator.pop(dialogContext, c),
                                          ))
                                      .toList(),
                                ),
                        ),
                      );
                      if (picked != null) classCtl.text = picked;
                    },
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: forikCtl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'ফরিক (খালি = পুরো ক্লাস)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: bnCtl,
                decoration: const InputDecoration(
                  labelText: 'নাম (বাংলা) *',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: enCtl,
                decoration: const InputDecoration(
                  labelText: 'নাম (ইংরেজি)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: mobCtl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'মোবাইল (01XXXXXXXXX)',
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
            onPressed: () async {
              final err = validate();
              if (err != null) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(err)));
                return;
              }
              final ok = await dialogContext
                  .read<TeacherProvider>()
                  .upsert(TeacherInfo(
                    className: classCtl.text,
                    forik: forikCtl.text,
                    nameBn: bnCtl.text,
                    nameEn: enCtl.text,
                    mobile: mobCtl.text,
                  ));
              if (!dialogContext.mounted) return;
              Navigator.pop(dialogContext);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(ok
                        ? '✅ শিক্ষকের তথ্য সংরক্ষিত'
                        : 'সংরক্ষণ করা যায়নি')));
              }
            },
          ),
        ],
      ),
    );
  }
}
