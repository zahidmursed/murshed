import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../models/student.dart';
import '../providers/student_provider.dart';
import '../utils/contact_helper.dart';
import '../utils/name_transliterator.dart';

/// স্তর ১ সম্পাদনা স্ক্রিন — নিরাপদ ফিল্ড (নাম/পিতা/মোবাইল/ঠিকানা/
/// মারহালা/বছর/পরীক্ষার নম্বর) অ্যাপের ভেতরেই বদলানো যায়।
/// দাখিলা/ক্লাস/ফরিক এখানে বদলানো যায় না (স্তর ২ — ফাইল-পাথ নির্ভরতা)।
class StudentEditScreen extends StatefulWidget {
  final Student student;
  const StudentEditScreen({super.key, required this.student});

  @override
  State<StudentEditScreen> createState() => _StudentEditScreenState();
}

class _StudentEditScreenState extends State<StudentEditScreen> {
  late final _name = TextEditingController(text: widget.student.stuName);
  late final _father = TextEditingController(text: widget.student.fatherName);
  late final _mobile =
      TextEditingController(text: widget.student.guardianMobile);
  late final _vill = TextEditingController(text: widget.student.addressVill);
  late final _po = TextEditingController(text: widget.student.addressPo);
  late final _ps = TextEditingController(text: widget.student.addressPs);
  late final _dist = TextEditingController(text: widget.student.addressDist);
  late final _marhala = TextEditingController(text: widget.student.marhala);
  late final _examYear = TextEditingController(text: widget.student.examYear);
  late final _dakhilaYear =
      TextEditingController(text: widget.student.dakhilaYear);
  late final _avgMonth = TextEditingController(text: widget.student.avgMonth);
  late final _avg1st = TextEditingController(text: widget.student.avg1st);
  late final _avg2nd = TextEditingController(text: widget.student.avg2nd);
  late final _avgFinal = TextEditingController(text: widget.student.avgFinal);
  late final _mother = TextEditingController(text: widget.student.motherName);
  late final _birthDate = TextEditingController(text: widget.student.birthDate);
  late final _birthCert =
      TextEditingController(text: widget.student.birthCertNo);
  // নামের ইংরেজি/আরবী রূপ (রিপোর্ট ফরমের জন্য — সবই ঐচ্ছিক)
  late final _stuEn = TextEditingController(text: widget.student.stuNameEn);
  late final _stuAr = TextEditingController(text: widget.student.stuNameAr);
  late final _fatherEn =
      TextEditingController(text: widget.student.fatherNameEn);
  late final _fatherAr =
      TextEditingController(text: widget.student.fatherNameAr);
  late final _motherEn =
      TextEditingController(text: widget.student.motherNameEn);
  late final _motherAr =
      TextEditingController(text: widget.student.motherNameAr);
  late final _class = TextEditingController(text: widget.student.className);
  late final _forik = TextEditingController(text: widget.student.forikNo);
  late final _level = TextEditingController(text: widget.student.classLevel);

  final _formKey = GlobalKey<FormState>();
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [
      _name,
      _father,
      _mobile,
      _mother,
      _birthDate,
      _birthCert,
      _stuEn,
      _stuAr,
      _fatherEn,
      _fatherAr,
      _motherEn,
      _motherAr,
      _vill,
      _po,
      _ps,
      _dist,
      _marhala,
      _examYear,
      _dakhilaYear,
      _avgMonth,
      _avg1st,
      _avg2nd,
      _avgFinal,
      _class,
      _forik,
      _level,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _validate() {
    if (_name.text.trim().isEmpty) return 'ছাত্রের নাম দিন';
    if (_class.text.trim().isEmpty) return 'ক্লাসের নাম দিন';
    final mobDigits = ContactHelper.normalizeLocalMobile(_mobile.text);
    if (mobDigits.isNotEmpty && mobDigits.length < 10) {
      return 'মোবাইল নম্বর সঠিক নয় (কমপক্ষে ১১ ডিজিট: 01XXXXXXXXX)';
    }
    final bd = _birthDate.text.trim();
    if (bd.isNotEmpty && !RegExp(r'^\d{2}-\d{2}-\d{4}$').hasMatch(bd)) {
      return 'জন্ম তারিখ DD-MM-YYYY ফরম্যাটে দিন (যেমন: 13-07-2003)';
    }
    for (final c in [_avgMonth, _avg1st, _avg2nd, _avgFinal]) {
      final v = c.text.trim();
      if (v.isNotEmpty && double.tryParse(v) == null) {
        return 'পরীক্ষার নম্বর শুধু সংখ্যা হতে পারে (যেমন: 87.5)';
      }
    }
    final level = _level.text.trim();
    if (level.isNotEmpty && int.tryParse(level) == null) {
      return 'ক্লাস লেভেল পূর্ণসংখ্যা হতে হবে (dropdown সাজার ক্রম)';
    }
    return null;
  }

  Future<void> _pickClass() async {
    final classes = context.read<StudentProvider>().classes;
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: classes.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text('ক্লাস-তালিকা খালি — নিজে লিখুন'),
              )
            : ListView(
                shrinkWrap: true,
                children: classes
                    .map((c) => ListTile(
                          title: Text(c),
                          onTap: () => Navigator.pop(sheetContext, c),
                        ))
                    .toList(),
              ),
      ),
    );
    if (picked != null && mounted) _class.text = picked;
  }

  // --- অটো-ফিল: বাংলা নাম থেকে ইংরেজি/আরবী (NameTransliterator) ---

  /// ইংরেজি নাম-ঘরের পাশে ✨ বাটন — ট্যাপে ওই ব্যক্তির ইংরেজি+আরবী দুটোই ভরে।
  Widget _autoSuffix(String who) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      tooltip: 'বাংলা থেকে অটো-পূরণ',
      icon: const Icon(Icons.auto_awesome, size: 18, color: Colors.teal),
      onPressed: () => _autoFill(who),
    );
  }

  Future<void> _autoFill(String who) async {
    final messenger = ScaffoldMessenger.of(context);
    final (String bn, TextEditingController en, TextEditingController ar,
            String label) =
        switch (who) {
      'stu' => (
          widget.student.stuName,
          _stuEn,
          _stuAr,
          'ছাত্র',
        ),
      'father' => (
          widget.student.fatherName,
          _fatherEn,
          _fatherAr,
          'পিতা',
        ),
      _ => (
          widget.student.motherName,
          _motherEn,
          _motherAr,
          'মাতা',
        ),
    };
    if (bn.trim().isEmpty) {
      messenger.showSnackBar(
          SnackBar(content: Text('$label: বাংলা নাম আগে লিখুন')));
      return;
    }
    // স্তর ১: নাম-ক্যাশ — আগে নিশ্চিত করা পূর্ণনাম-জোড়া (১০০% নির্ভুল)
    final cached = await DatabaseHelper.instance
        .lookupNameCache(NameTransliterator.cacheKey(bn));
    if (!mounted) return;
    if (cached != null) {
      setState(() {
        if (cached.english.isNotEmpty) en.text = cached.english;
        if (cached.arabic.isNotEmpty) ar.text = cached.arabic;
      });
      messenger.showSnackBar(SnackBar(
          content: Text('✨ $label: আগে নিশ্চিত করা নাম থেকে পূরণ — সেভ করুন')));
      return;
    }
    // স্তর ২: ডিকশনারি/নিয়ম
    final r = NameTransliterator.transliterate(bn);
    setState(() {
      en.text = r.english;
      ar.text = r.arabic;
    });
    messenger.showSnackBar(SnackBar(content: Text(_resultMessage(label, r))));
  }

  Future<void> _autoFillAll() async {
    final messenger = ScaffoldMessenger.of(context);
    final rows = [
      ('ছাত্র', widget.student.stuName, _stuEn, _stuAr),
      ('পিতা', widget.student.fatherName, _fatherEn, _fatherAr),
      ('মাতা', widget.student.motherName, _motherEn, _motherAr),
    ];
    var filled = 0, empty = 0, cacheHits = 0, tokens = 0, unknown = 0;
    for (final (_, bn, en, ar) in rows) {
      if (bn.trim().isEmpty) {
        empty++;
        continue;
      }
      // স্তর ১: ক্যাশ — আগে নিশ্চিত করা পূর্ণনাম
      final cached = await DatabaseHelper.instance
          .lookupNameCache(NameTransliterator.cacheKey(bn));
      if (!mounted) return;
      setState(() {
        if (cached != null) {
          if (cached.english.isNotEmpty) en.text = cached.english;
          if (cached.arabic.isNotEmpty) ar.text = cached.arabic;
          cacheHits++;
          filled++;
        } else {
          // স্তর ২: ডিকশনারি/নিয়ম
          final r = NameTransliterator.transliterate(bn);
          en.text = r.english;
          ar.text = r.arabic;
          filled++;
          tokens += r.tokens;
          unknown += r.unknown;
        }
      });
    }
    if (filled == 0) {
      messenger.showSnackBar(
          const SnackBar(content: Text('বাংলা নাম খালি — আগে লিখুন')));
      return;
    }
    final detail = empty > 0 ? ' ($empty জনের বাংলা নাম খালি)' : '';
    final parts = <String>[];
    if (cacheHits > 0) parts.add('$cacheHits জন আগের নিশ্চিত নাম থেকে');
    if (tokens > 0) {
      parts.add(unknown == 0
          ? 'ডিকশনারি থেকে সম্পূর্ণ মিল'
          : '$unknown/$tokens টোকেন অনুমিত');
    }
    messenger.showSnackBar(SnackBar(
      content: Text('✨ $filled জন পূরণ — ${parts.join('; ')} — '
          'যাচাই করে সেভ করুন$detail'),
    ));
  }

  String _resultMessage(String label, TranslitResult r) {
    if (r.isEmpty) return '$label: বাংলা নাম খালি';
    return r.allKnown
        ? '✨ $label: ডিকশনারি থেকে পূরণ — যাচাই করে সেভ করুন'
        : '⚠️ $label: ${r.unknown}/${r.tokens} টোকেন অনুমিত (ডিকশনারিতে নেই) '
            '— বানান যাচাই করুন';
  }

  /// সফল সেভের পরে নাম-জোড়া ক্যাশে লেখা — ব্যবহারের সাথে অটো-ফিল
  /// আরও নির্ভুল হয় (ইউজার সেভের আগেই মানগুলো দেখে যাচাই করে ফেলে)।
  Future<void> _cacheNames() async {
    final rows = [
      (_name.text.trim(), _stuEn.text.trim(), _stuAr.text.trim()),
      (_father.text.trim(), _fatherEn.text.trim(), _fatherAr.text.trim()),
      (_mother.text.trim(), _motherEn.text.trim(), _motherAr.text.trim()),
    ];
    for (final (bn, en, ar) in rows) {
      if (bn.isEmpty || (en.isEmpty && ar.isEmpty)) continue;
      try {
        await DatabaseHelper.instance
            .saveNameCache(NameTransliterator.cacheKey(bn), en, ar);
      } catch (e) {
        debugPrint('Name cache save failed: $e');
      }
    }
  }

  Future<void> _save() async {
    final err = _validate();
    final messenger = ScaffoldMessenger.of(context);
    if (err != null) {
      messenger.showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    setState(() => _saving = true);
    final updated = widget.student.copyWith(
      stuName: _name.text.trim(),
      fatherName: _father.text.trim(),
      guardianMobile: ContactHelper.normalizeLocalMobile(_mobile.text).trim(),
      addressVill: _vill.text.trim(),
      addressPo: _po.text.trim(),
      addressPs: _ps.text.trim(),
      addressDist: _dist.text.trim(),
      marhala: _marhala.text.trim(),
      examYear: _examYear.text.trim(),
      dakhilaYear: _dakhilaYear.text.trim(),
      avgMonth: _avgMonth.text.trim(),
      avg1st: _avg1st.text.trim(),
      avg2nd: _avg2nd.text.trim(),
      avgFinal: _avgFinal.text.trim(),
      motherName: _mother.text.trim(),
      birthDate: _birthDate.text.trim(),
      birthCertNo: _birthCert.text.trim(),
      stuNameEn: _stuEn.text.trim(),
      stuNameAr: _stuAr.text.trim(),
      fatherNameEn: _fatherEn.text.trim(),
      fatherNameAr: _fatherAr.text.trim(),
      motherNameEn: _motherEn.text.trim(),
      motherNameAr: _motherAr.text.trim(),
      className: _class.text.trim(),
      forikNo: _forik.text.trim(),
      classLevel: _level.text.trim(),
    );
    // স্তর ২: ক্লাস/ফরিক বদলালে provider ফাইল-মুভ সহ সব সামলায়
    final result =
        await context.read<StudentProvider>().editStudentIdentity(updated);
    if (!mounted) return;
    setState(() => _saving = false);
    if (result.ok) {
      // সেভ হওয়া নাম-জোড়া ক্যাশে রাখা — পরেরবার এক-ট্যাপে নির্ভুল অটো-ফিল
      await _cacheNames();
      if (!mounted) return;
      var msg = '✅ তথ্য সংরক্ষিত হয়েছে';
      if (result.moved > 0) {
        msg += ' · ${result.moved} ফাইল নতুন ফোল্ডারে সরানো হয়েছে';
      }
      if (result.failed > 0) {
        msg += ' · ⚠️ ${result.failed} ফাইল সরানো যায়নি (পুরনো জায়গায় আছে)';
      }
      messenger.showSnackBar(SnackBar(content: Text(msg)));
      Navigator.pop(context);
    } else {
      messenger.showSnackBar(
        const SnackBar(content: Text('সংরক্ষণ করা যায়নি — আবার চেষ্টা করুন')),
      );
    }
  }

  TextFormField _field(
    String label,
    TextEditingController controller, {
    TextInputType? keyboardType,
    List<TextInputFormatter>? formatters,
    String? hint,
    String? helper,
    bool rtl = false,
    Widget? suffix,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: formatters,
      textDirection: rtl ? TextDirection.rtl : null,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helper,
        helperMaxLines: 2,
        suffixIcon: suffix,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const Divider(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  static final _phoneFormatters = [
    FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-\s]')),
  ];
  static final _numFormatters = [
    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('তথ্য সম্পাদনা: ${widget.student.dakhila}'),
        backgroundColor: Colors.teal,
        actions: [
          IconButton(
            tooltip: 'সংরক্ষণ',
            icon: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save),
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _section('মৌলিক তথ্য', [
                _field('ছাত্রের নাম *', _name),
                const SizedBox(height: 10),
                _field('পিতার নাম', _father),
                const SizedBox(height: 10),
                _field('মাতার নাম', _mother),
                const SizedBox(height: 10),
                _field('জন্ম তারিখ (DD-MM-YYYY)', _birthDate),
                const SizedBox(height: 10),
                _field('জন্মসনদ নম্বর', _birthCert),
                const SizedBox(height: 10),
                _field('অভিভাবকের মোবাইল', _mobile,
                    keyboardType: TextInputType.phone,
                    formatters: _phoneFormatters),
              ]),
              const SizedBox(height: 12),
              _section('নাম — ইংরেজি ও আরবী (রিপোর্ট ফরমের জন্য, ঐচ্ছিক)', [
                FilledButton.tonalIcon(
                  onPressed: _autoFillAll,
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: const Text('সব অটো-পূরণ (বাংলা থেকে)'),
                ),
                const SizedBox(height: 10),
                _field('ছাত্রের নাম — ইংরেজি', _stuEn,
                    helper: 'বাংলা: ${widget.student.stuName}',
                    suffix: _autoSuffix('stu')),
                const SizedBox(height: 10),
                _field('ছাত্রের নাম — আরবী', _stuAr,
                    rtl: true,
                    helper: 'বাংলা: ${widget.student.stuName}'),
                const SizedBox(height: 10),
                _field('পিতার নাম — ইংরেজি', _fatherEn,
                    helper: 'বাংলা: ${widget.student.fatherName}',
                    suffix: _autoSuffix('father')),
                const SizedBox(height: 10),
                _field('পিতার নাম — আরবী', _fatherAr,
                    rtl: true,
                    helper: 'বাংলা: ${widget.student.fatherName}'),
                const SizedBox(height: 10),
                _field('মাতার নাম — ইংরেজি', _motherEn,
                    helper: 'বাংলা: ${widget.student.motherName}',
                    suffix: _autoSuffix('mother')),
                const SizedBox(height: 10),
                _field('মাতার নাম — আরবী', _motherAr,
                    rtl: true,
                    helper: 'বাংলা: ${widget.student.motherName}'),
              ]),
              const SizedBox(height: 12),
              _section('শ্রেণি ও ফরিক (ছবির ফোল্ডার বদলাবে)', [
                _field('ক্লাস *', _class,
                    hint: 'যেমন: হিফয সবকী',
                    suffix: IconButton(
                      tooltip: 'ক্লাস-তালিকা থেকে বাছুন',
                      icon: const Icon(Icons.arrow_drop_down),
                      onPressed: _pickClass,
                    )),
                const SizedBox(height: 10),
                _field('ফরিক (খালি রাখা যায়)', _forik,
                    keyboardType: TextInputType.number),
                const SizedBox(height: 10),
                _field('ক্লাস লেভেল (dropdown সাজার সংখ্যা)', _level,
                    keyboardType: TextInputType.number),
              ]),
              const SizedBox(height: 12),
              _section('ঠিকানা', [
                _field('গ্রাম/মহল্লা', _vill),
                const SizedBox(height: 10),
                _field('ডাকঘর', _po),
                const SizedBox(height: 10),
                _field('থানা/উপজেলা', _ps),
                const SizedBox(height: 10),
                _field('জেলা', _dist),
              ]),
              const SizedBox(height: 12),
              _section('শিক্ষা ও বছর', [
                _field('মারহালা', _marhala),
                const SizedBox(height: 10),
                _field('পরীক্ষার বছর', _examYear,
                    keyboardType: TextInputType.number),
                const SizedBox(height: 10),
                _field('দাখিলা বছর', _dakhilaYear,
                    keyboardType: TextInputType.number),
              ]),
              const SizedBox(height: 12),
              _section('পরীক্ষার নম্বর', [
                _field('মাসিক পরীক্ষা', _avgMonth,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    formatters: _numFormatters),
                const SizedBox(height: 10),
                _field('প্রথম সাময়িক', _avg1st,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    formatters: _numFormatters),
                const SizedBox(height: 10),
                _field('দ্বিতীয় সাময়িক', _avg2nd,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    formatters: _numFormatters),
                const SizedBox(height: 10),
                _field('বার্ষিক পরীক্ষা', _avgFinal,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    formatters: _numFormatters),
              ]),
              const SizedBox(height: 8),
              Text(
                '⚠️ ক্লাস/ফরিক বদলালে তোলা ছবি ও ডকুমেন্ট নতুন ফোল্ডারে '
                'সরে যাবে। দাখিলা: ${widget.student.dakhila} — '
                'পরিবর্তনযোগ্য নয়।',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save),
                label: Text(_saving ? 'সংরক্ষণ হচ্ছে...' : 'সংরক্ষণ করুন'),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
