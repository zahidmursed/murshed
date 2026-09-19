// @dart=2.19
// ignore_for_file: avoid_print, avoid_relative_lib_imports
// BUILD-TIME TOOL — যাচাইকৃত নাম-কর্পাস (২১,০০০ সারির TSV) থেকে
// lib/utils/translit/name_corpus.dart জেনারেট করে।
//
// ইনপুট (ক্রমে খোঁজে): tool/_corpus_copy.txt → assets/name.txt
//   ফরম্যাট: UTF-16LE, ট্যাব-আলাদা, হেডারসহ: Bangla_Name/English_Name/Arabic_Name/Gender
//   assets/name.txt অন্য প্রোগ্রামে (Excel ইত্যাদি) খোলা থাকলে Dart সরাসরি পড়তে
//   পারে না — তখন shared-read কপি নিন (PowerShell):
//     $fs=[IO.FileStream]::new('assets\name.txt','Open','Read','ReadWrite');
//     $fs.CopyTo([IO.File]::OpenWrite('tool\_corpus_copy.txt')); $fs.Close()
//
// অ্যালাইনমেন্ট: EN ভোট হয় যেসব সারিতে বাংলা-টোকেন সংখ্যা == ইংরেজি-টোকেন সংখ্যা;
// AR ভোট স্বাধীনভাবে (বাংলা == আরবী সংখ্যা)। টপ-ভোট < ৬০% শেয়ার (≥২ ভোটে) →
// conflict — এন্ট্রি স্কিপ + রিপোর্টে তালিকা।
//
// চালানো: dart run tool/build_name_corpus.dart
import 'dart:convert';
import 'dart:io';

import '../lib/utils/name_transliterator.dart';

String _esc(String s) => s.runes.map((c) {
      if (c == 0x5c || c == 0x27 || c > 0x7e) {
        return '\\u${c.toRadixString(16).toUpperCase().padLeft(4, '0')}';
      }
      return String.fromCharCode(c);
    }).join();

String _decodeUtf16le(List<int> b) {
  final sb = StringBuffer();
  for (var i = 2; i + 1 < b.length; i += 2) {
    sb.writeCharCode(b[i] | (b[i + 1] << 8));
  }
  return sb.toString();
}

String _titleCase(String w) {
  if (w.isEmpty) return w;
  if (w == w.toLowerCase() || w == w.toUpperCase()) {
    return w[0].toUpperCase() + w.substring(1).toLowerCase();
  }
  return w;
}

String _normEn(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');

final _latinSplit = RegExp(r"[^A-Za-z']+");

/// ইংরেজি নাম → লোয়ার-কেস ল্যাটিন টোকেন ("Md. Rahman" → [md, rahman])।
List<String> _latinTokens(String s) => s
    .split(_latinSplit)
    .where((t) => t.isNotEmpty)
    .map((t) => t.toLowerCase())
    .toList();

void main(List<String> args) {
  final candidates = [
    if (args.isNotEmpty) args[0],
    'tool/_corpus_copy.txt',
    'assets/name.txt',
  ];
  File? src;
  for (final p in candidates) {
    if (File(p).existsSync()) {
      src = File(p);
      break;
    }
  }
  if (src == null) {
    stderr.writeln('ERROR: corpus not found (দেখুন tool/build_name_corpus.dart হেডার)');
    exit(1);
  }
  stdout.writeln('source: ${src.path}');

  final raw = _decodeUtf16le(src.readAsBytesSync());
  final lines = raw.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList();
  final rows = <List<String>>[];
  for (final l in lines.skip(1)) {
    final c = l.split('\t');
    if (c.length < 3) continue;
    final b = c[0].trim(), e = c[1].trim(), a = c[2].trim();
    if (b.isEmpty || e.isEmpty || a.isEmpty) continue;
    rows.add([b, e, a]);
  }
  // ---- token-level majority vote ----
  final enVotes = <String, Map<String, int>>{};
  final arVotes = <String, Map<String, int>>{};
  var alignedEn = 0, alignedAr = 0;

  for (final r in rows) {
    final bt = NameTransliterator.tokenize(r[0]);
    final et = _latinTokens(r[1]);
    final at = NameTransliterator.tokenize(r[2]);
    if (bt.isNotEmpty && bt.length == et.length) {
      alignedEn++;
      for (var i = 0; i < bt.length; i++) {
        enVotes.putIfAbsent(bt[i], () => {})[et[i]] =
            (enVotes[bt[i]]?[et[i]] ?? 0) + 1;
      }
    }
    if (bt.isNotEmpty && bt.length == at.length) {
      alignedAr++;
      for (var i = 0; i < bt.length; i++) {
        arVotes.putIfAbsent(bt[i], () => {})[at[i]] =
            (arVotes[bt[i]]?[at[i]] ?? 0) + 1;
      }
    }
  }

  // ---- entries ----
  final conflicts = <String>[];
  final overrides = <String>[];
  final entries = <String, List<String>>{};
  var usedAlias = 0;

  void vote(String b, Map<String, Map<String, int>> votes, void Function(String, int) add) {
    final m = votes[b];
    if (m == null || m.isEmpty) return;
    var best = '', bestN = 0, total = 0;
    m.forEach((k, v) {
      total += v;
      if (v > bestN) { best = k; bestN = v; }
    });
    if (total >= 2 && bestN / total < 0.60) {
      if (conflicts.length < 80) conflicts.add('$b\t$best\t$bestN/$total');
      return;
    }
    add(best, bestN);
  }

  for (final b in enVotes.keys.toSet()..addAll(arVotes.keys)) {
    final key = NameTransliterator.canonicalToken(b);
    var en = '', ar = '';
    var nEn = 0, nAr = 0;
    vote(b, enVotes, (v, n) { en = v; nEn = n; });
    vote(b, arVotes, (v, n) { ar = v; nAr = n; });
    if (key != b) usedAlias++;
    if (en.isEmpty || ar.isEmpty) {
      if (conflicts.length < 80) conflicts.add('$b\tPARTIAL\tEn="$en" Ar="$ar"');
      continue;
    }
    final oldEn = NameTransliterator.dictEntry(b)?.$1;
    final oldAr = NameTransliterator.dictEntry(b)?.$2;
    final enFinal = (oldEn != null && nEn < 5) ? oldEn : _titleCase(en);
    final arFinal = (oldAr != null && nAr < 5) ? oldAr : ar;
    if (oldEn != null && _normEn(oldEn) != _normEn(enFinal)) {
      if (overrides.length < 60) overrides.add('$key\tEN: $oldEn → $enFinal ($nEn votes)');
    }
    if (oldAr != null && oldAr != arFinal) {
      if (overrides.length < 60) overrides.add('$key\tAR: $oldAr → $arFinal ($nAr votes)');
    }
    entries[key] = [enFinal, arFinal];
  }

  // হাতে-লেখা ডিকশনারির অনুপস্থিত এন্ট্রিগুলো ধরে রাখা — কর্পাস শুধু বর্তমান
  // পুলের টোকেন জানে; পুরনো জ্ঞান (মোসাঃ, মৃত, উল্লাহ …) হারালে অনেক নাম ফাঁকি যাবে।
  for (final b in NameTransliterator.dictTokens) {
    final key = NameTransliterator.canonicalToken(b);
    if (entries.containsKey(key)) continue;
    final e = NameTransliterator.dictEntry(b);
    if (e == null) continue;
    entries[key] = [e.$1, e.$2];
  }
  stdout.writeln('after merge with hand dict: ${entries.length} entries');

  // ---- generate ----
  final sb = StringBuffer()
    ..writeln("// GENERATED by tool/build_name_corpus.dart — হাতে সম্পাদনা নয়।")
    ..writeln('// উৎস: ${src.path} (${rows.length} rows) • '
        'alignedEn=$alignedEn alignedAr=$alignedAr • entries=${entries.length} '
        '(alias-based=$usedAlias) • conflicts=${conflicts.length}')
    ..writeln('///')
    ..writeln('/// লুকআপ সবসময় নরমালাইজড কী-তে (NameTransliterator._dictN পথ)।')
    ..writeln('library;')
    ..writeln()
    ..writeln('const Map<String, List<String>> kNameCorpus = {');
  final keys = entries.keys.toList()..sort();
  for (final k in keys) {
    final e = entries[k]!;
    sb.writeln("  '${_esc(k)}': ['${_esc(e[0])}', '${_esc(e[1])}'],");
  }
  sb..writeln('};')..writeln();

  Directory('lib/utils/translit').createSync(recursive: true);
  File('lib/utils/translit/name_corpus.dart')
      .writeAsStringSync(sb.toString(), encoding: utf8);

  final rep = StringBuffer()
    ..writeln('rows=${rows.length} alignedEn=$alignedEn alignedAr=$alignedAr')
    ..writeln('distinctTokens: En=${enVotes.length} Ar=${arVotes.length}')
    ..writeln('entries=${entries.length} (via-alias=$usedAlias) '
        'conflicts=${conflicts.length} overrides=${overrides.length}')
    ..writeln()
    ..writeln('--- first 10 parsed rows ---')
    ..write(rows.take(10).map((r) => r.join(' | ')).join('\n'))
    ..writeln()
    ..writeln('--- first 10 generated entries ---')
    ..write(keys.take(10).map((k) => '$k => ${entries[k]!.join(' | ')}').join('\n'))
    ..writeln()
    ..writeln('--- dict overrides (first 60) ---')
    ..write(overrides.join('\n'))
    ..writeln()
    ..writeln('--- conflicts (first 80) ---')
    ..write(conflicts.join('\n'));
  File('tool/_corpus_report.txt').writeAsStringSync(rep.toString(), encoding: utf8);
  print('OK: lib/utils/translit/name_corpus.dart (${entries.length} entries), '
      'conflicts=${conflicts.length}');
}

