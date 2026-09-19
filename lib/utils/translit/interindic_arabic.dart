import 'bengali_interindic.dart';

/// রুলের প্রেক্ষাপট — ICU-র `$nonword` / `$wordBoundary` / `[[:L:][:M:]]`।
enum _Ctx { none, wordEnd, wordInitial, afterLetter }

/// একটি ম্যাচের ফল।
class _Hit {
  final int length;
  final String output;
  const _Hit(this.length, this.output);
}

/// **CLDR/ICU `InterIndic_Arabic` টেবিলের ডার্ট পোর্ট — বাংলা → আরবী।**
/// সূত্র: `icu4c/source/data/translit/InterIndic_Arabic.txt` (Unicode License)।
///
/// ICU-র চেইন অনুকরণ করা হয়: `Bengali → InterIndic → Arabic`, অর্থাৎ
/// [BengaliInterIndic.convert] চালিয়ে তারপর নিচের রুলগুলো।
///
/// ICU-র মতোই: একই অবস্থানে একাধিক রুল মিললে **দীর্ঘতম প্যাটার্ন** জেতে,
/// সমান হলে টেবিলের ক্রম (উপরের রুল আগে)।
///
/// সচেতন সিদ্ধান্ত: ICU-র কিছু রুলের RHS-এ ফাঁকা অক্ষর আছে (`→ه ا`) —
/// নাম-ট্রান্সলিটারেশনে শব্দের ভেতরে ফাঁকা অনাকাঙ্ক্ষিত, তাই এখানে ওগুলো
/// জোড়া অক্ষর হিসেবেই বসানো হয় (`ها`)। `$alif` সংকোচন রুলটিও রাখা হয়েছে।
class InterIndicArabic {
  InterIndicArabic._();

  /// ICU `InterIndic_Arabic.txt`-এর রুলগুলো (সোর্স-ক্রমে; দীর্ঘ প্যাটার্ন জেতে)।
  static const List<_Rule> _rules = [
    // --- বিশেষ শব্দ-শেষ রূপ (किया/दिया/कि ধাঁচ) ---
    _Rule('\uE015\uE03F\uE02F\uE03E', _Ctx.wordEnd, 'كيا'),
    _Rule('\uE026\uE03F\uE02F\uE03E', _Ctx.wordEnd, 'ديا'),
    _Rule('\uE015\uE03F', _Ctx.wordEnd, 'كي'),
    _Rule('\uE039\uE048', _Ctx.none, 'هي'),
    // --- অনুস্বার / চন্দ্রবিন্দু / বিসর্গ ---
    _Rule('\uE001', _Ctx.wordEnd, 'ن'),
    _Rule('\uE001', _Ctx.none, 'ن'),
    _Rule('\uE002', _Ctx.wordEnd, 'ن'),
    _Rule('\uE002', _Ctx.none, 'ن'),
    _Rule('\uE003', _Ctx.none, 'ها'),
    // --- স্বরবর্ণ ---
    _Rule('\uE004', _Ctx.none, 'ا'),
    _Rule('\uE005', _Ctx.none, 'ا'), // অ
    _Rule('\uE006', _Ctx.none, 'ا\u0653'), // আ (alif with maddah)
    _Rule('\uE007', _Ctx.afterLetter, 'ي'), // ই — অক্ষরের পরে
    _Rule('\uE007', _Ctx.wordInitial, 'إ'), // ই — শব্দের শুরুতে
    _Rule('\uE008', _Ctx.afterLetter, 'ي'), // ঈ
    _Rule('\uE008', _Ctx.wordInitial, 'إ'),
    _Rule('\uE009', _Ctx.none, 'و'), // উ
    _Rule('\uE00A', _Ctx.none, 'و'), // ঊ
    _Rule('\uE00B', _Ctx.none, 'ر'), // ঋ
    _Rule('\uE00C', _Ctx.none, 'ل'), // ঌ
    _Rule('\uE00D', _Ctx.none, 'اي'),
    _Rule('\uE00E', _Ctx.none, 'ي'),
    _Rule('\uE00F', _Ctx.wordInitial, 'إي'), // এ — শব্দের শুরুতে
    _Rule('\uE00F', _Ctx.wordEnd, 'ي'),
    _Rule('\uE00F', _Ctx.none, 'ي'),
    _Rule('\uE010', _Ctx.wordEnd, 'اي'), // ঐ
    _Rule('\uE010', _Ctx.none, 'اي'),
    _Rule('\uE011', _Ctx.none, 'او'),
    _Rule('\uE012', _Ctx.none, 'او'),
    _Rule('\uE013', _Ctx.none, 'او'), // ও
    _Rule('\uE014', _Ctx.none, 'او'), // ঔ
    // --- ব্যঞ্জনবর্ণ (CLDR ম্যাপ: অ-আরবী বর্ণগুলো নিকটতম আরবীতে) ---
    _Rule('\uE015', _Ctx.none, 'ك'), // ক
    _Rule('\uE016', _Ctx.none, 'كه'), // খ
    _Rule('\uE017', _Ctx.none, 'ج'), // গ
    _Rule('\uE018', _Ctx.none, 'جه'), // ঘ
    _Rule('\uE019', _Ctx.none, 'نج'), // ঙ
    _Rule('\uE01A', _Ctx.none, 'تش'), // চ
    _Rule('\uE01B', _Ctx.none, 'تشه'), // ছ
    _Rule('\uE01C', _Ctx.none, 'ج'), // জ
    _Rule('\uE01D', _Ctx.none, 'جه'), // ঝ
    _Rule('\uE01E', _Ctx.none, 'ن'), // ঞ
    _Rule('\uE01F', _Ctx.none, 'ط'), // ট
    _Rule('\uE020', _Ctx.none, 'طه'), // ঠ
    _Rule('\uE021', _Ctx.none, 'د'), // ড
    _Rule('\uE022', _Ctx.none, 'ده'), // ঢ
    _Rule('\uE023', _Ctx.none, 'ن'), // ণ
    _Rule('\uE024', _Ctx.none, 'ت'), // ত
    _Rule('\uE025', _Ctx.none, 'ته'), // থ
    _Rule('\uE026', _Ctx.none, 'د'), // দ
    _Rule('\uE027', _Ctx.none, 'ده'), // ধ
    _Rule('\uE028', _Ctx.none, 'ن'), // ন
    _Rule('\uE029', _Ctx.none, 'ن'),
    _Rule('\uE02A', _Ctx.none, 'ب'), // প
    _Rule('\uE02B', _Ctx.none, 'به'), // ফ
    _Rule('\uE02C', _Ctx.none, 'ب'), // ব
    _Rule('\uE02D', _Ctx.none, 'به'), // ভ
    _Rule('\uE02E', _Ctx.none, 'م'), // ম
    _Rule('\uE02F', _Ctx.none, 'ي'), // য / য়
    _Rule('\uE030', _Ctx.none, 'ر'), // র
    _Rule('\uE031', _Ctx.none, 'ر'),
    _Rule('\uE032', _Ctx.none, 'ل'), // ল
    _Rule('\uE033', _Ctx.none, 'ر'),
    _Rule('\uE034', _Ctx.none, 'ر'),
    _Rule('\uE035', _Ctx.none, 'و'), // ৱ/ভ
    _Rule('\uE036', _Ctx.none, 'ش'), // শ
    _Rule('\uE037', _Ctx.none, 'ش'), // ষ
    _Rule('\uE038', _Ctx.none, 'س'), // স
    _Rule('\uE039', _Ctx.none, 'ه'), // হ
    // --- মাত্রা (স্বরচিহ্ন) ---
    _Rule('\uE03C', _Ctx.none, ''), // ় নুকতা — আরবীতে আলাদা চিহ্ন নেই
    _Rule('\uE03D', _Ctx.none, ''), // ঽ
    _Rule('\uE03E', _Ctx.none, 'ا'), // া
    _Rule('\uE03F', _Ctx.none, 'ي'), // ি
    _Rule('\uE040', _Ctx.none, 'ي'), // ী
    _Rule('\uE041', _Ctx.none, 'و'), // ু
    _Rule('\uE042', _Ctx.none, 'و'), // ূ
    _Rule('\uE043', _Ctx.none, 'ر'), // ৃ
    _Rule('\uE044', _Ctx.none, 'ر'),
    _Rule('\uE045', _Ctx.none, 'ن'),
    _Rule('\uE046', _Ctx.none, 'ي'),
    _Rule('\uE047', _Ctx.wordEnd, 'ي'), // ে
    _Rule('\uE047', _Ctx.none, 'ي'),
    _Rule('\uE048', _Ctx.wordEnd, 'اي'), // ৈ
    _Rule('\uE048', _Ctx.none, 'اي'),
    _Rule('\uE049', _Ctx.none, 'و'),
    _Rule('\uE04A', _Ctx.none, 'او'),
    _Rule('\uE04B', _Ctx.none, 'و'), // ো
    _Rule('\uE04C', _Ctx.none, 'او'), // ৌ
    _Rule('\uE04D', _Ctx.none, ''), // ্ হসন্ত — বাদ
    _Rule('\uE050', _Ctx.none, 'او'), // ॐ
    // --- উর্দু/ফারসি সামঞ্জস্য ফর্ম ---
    _Rule('\uE058', _Ctx.none, 'ق'),
    _Rule('\uE059', _Ctx.none, 'خ'),
    _Rule('\uE05A', _Ctx.none, 'غ'),
    _Rule('\uE05B', _Ctx.none, 'ز'),
    _Rule('\uE05C', _Ctx.none, 'ر'),
    _Rule('\uE05D', _Ctx.none, 'ره'),
    _Rule('\uE05E', _Ctx.none, 'ف'),
    _Rule('\uE05F', _Ctx.none, 'ي'),
    _Rule('\uE060', _Ctx.none, 'ر'),
    _Rule('\uE061', _Ctx.none, 'ل'),
    _Rule('\uE062', _Ctx.none, 'ل'),
    _Rule('\uE063', _Ctx.none, 'ل'),
    // --- যতিচিহ্ন ও সংখ্যা ---
    _Rule('\uE064', _Ctx.none, '۔'),
    _Rule('\uE065', _Ctx.none, '۔'),
    _Rule('\uE066', _Ctx.none, '.'),
    _Rule('\uE067', _Ctx.none, '١'),
    _Rule('\uE068', _Ctx.none, '٢'),
    _Rule('\uE069', _Ctx.none, '٣'),
    _Rule('\uE06A', _Ctx.none, '٤'),
    _Rule('\uE06B', _Ctx.none, '٥'),
    _Rule('\uE06C', _Ctx.none, '٦'),
    _Rule('\uE06D', _Ctx.none, '٧'),
    _Rule('\uE06E', _Ctx.none, '٨'),
    _Rule('\uE06F', _Ctx.none, '٩'),
    _Rule('\uE070', _Ctx.none, '.'),
    _Rule('\uE082', _Ctx.none, ''),
  ];

  /// বাংলা টেক্সট → আরবী লিপি (ইনপুট নরমালাইজেশন সহ)।
  static String transliterate(String bengali) =>
      applyToInterIndic(BengaliInterIndic.convert(bengali));

  /// InterIndic কোড-পয়েন্টের স্ট্রিং → আরবী।
  static String applyToInterIndic(String src) {
    final buf = StringBuffer();
    var i = 0;
    while (i < src.length) {
      final hit = _matchAt(src, i);
      if (hit != null) {
        buf.write(hit.output);
        i += hit.length;
      } else {
        final c = src.codeUnitAt(i);
        // ম্যাপ না থাকা InterIndic কোড (যেমন ৲/৴/হসন্ত-অবশিষ্ট) ফেলে দিই —
        // private-use অক্ষর কখনো আউটপুটে যেতে পারে না।
        if (!_isInterIndic(c)) buf.writeCharCode(c);
        i++;
      }
    }
    return _collapseAlif(buf.toString()).trim();
  }

  static bool _isInterIndic(int c) => c >= 0xE000 && c <= 0xE0FF;

  static _Hit? _matchAt(String s, int i) {
    _Hit? best;
    for (final rule in _rules) {
      final p = rule.pattern;
      if (i + p.length > s.length) continue;
      var same = true;
      for (var k = 0; k < p.length; k++) {
        if (s.codeUnitAt(i + k) != p.codeUnitAt(k)) {
          same = false;
          break;
        }
      }
      if (!same) continue;
      if (!_contextOk(rule.ctx, s, i, p.length)) continue;
      if (best == null || p.length > best.length) {
        best = _Hit(p.length, rule.output);
      }
    }
    return best;
  }

  static bool _contextOk(_Ctx ctx, String s, int i, int len) {
    switch (ctx) {
      case _Ctx.none:
        return true;
      case _Ctx.wordEnd:
        final next = i + len;
        return next >= s.length || !_isInterIndic(s.codeUnitAt(next));
      case _Ctx.wordInitial:
        return i == 0 || !_isInterIndic(s.codeUnitAt(i - 1));
      case _Ctx.afterLetter:
        return i > 0 && _isInterIndic(s.codeUnitAt(i - 1));
    }
  }

  // --- `$alif` সংকোচন: ($alif) $alif+ → $1 -------------------------------

  static const Set<int> _alif = {0x0623, 0x0625, 0x0622, 0x0627};

  static bool _isArabicMark(int c) =>
      (c >= 0x0610 && c <= 0x061A) ||
      (c >= 0x064B && c <= 0x065F) ||
      c == 0x0670 ||
      (c >= 0x06D6 && c <= 0x06DC) ||
      (c >= 0x06DF && c <= 0x06E4) ||
      (c >= 0x06E7 && c <= 0x06E8) ||
      (c >= 0x06EA && c <= 0x06ED) ||
      c == 0x0653;

  static String _collapseAlif(String s) {
    final out = StringBuffer();
    var i = 0;
    while (i < s.length) {
      final c = s.codeUnitAt(i);
      if (_alif.contains(c)) {
        out.writeCharCode(c);
        i++;
        while (i < s.length && _isArabicMark(s.codeUnitAt(i))) {
          out.writeCharCode(s.codeUnitAt(i));
          i++;
        }
        // পরপর আসা alif-খণ্ড (marks-সহ) বাদ
        while (i < s.length) {
          var j = i;
          while (j < s.length && _isArabicMark(s.codeUnitAt(j))) {
            j++;
          }
          if (j < s.length && _alif.contains(s.codeUnitAt(j))) {
            i = j + 1;
            while (i < s.length && _isArabicMark(s.codeUnitAt(i))) {
              i++;
            }
          } else {
            break;
          }
        }
        continue;
      }
      out.writeCharCode(c);
      i++;
    }
    return out.toString();
  }
}

/// একটি ICU রুল: pattern (InterIndic) + প্রেক্ষাপট + আরবী আউটপুট।
class _Rule {
  final String pattern;
  final _Ctx ctx;
  final String output;
  const _Rule(this.pattern, this.ctx, this.output);
}