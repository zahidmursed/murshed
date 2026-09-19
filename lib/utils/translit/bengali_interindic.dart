import 'bengali_text.dart';

/// **CLDR/ICU `Bengali_InterIndic` টেবিলের ডার্ট পোর্ট**
/// সূত্র: `icu4c/source/data/translit/Bengali_InterIndic.txt` (Unicode License)।
///
/// ICU-র চেইন: `[ Script=Bengali ] → NFD → Bengali-InterIndic → InterIndic-Arabic
/// → NFC`। এখানে NFD-এর কাজটা [BengaliText.normalize] করে, টেবিলটা এই ক্লাস।
///
/// টেবিলটি `(বাংলা, InterIndic)` জোড়ার একটি সমতল স্ট্রিং — সব অক্ষর `\u`
/// escape-এ লেখা, তাই এনকোডিং-দুর্ঘটনায় এটি নষ্ট হতে পারে না।
class BengaliInterIndic {
  BengaliInterIndic._();

  static const String _pairs =
      '\u0981\uE001\u0982\uE002\u0983\uE003\u0985\uE005\u0986\uE006'
      '\u0987\uE007\u0988\uE008\u0989\uE009\u098A\uE00A\u098B\uE00B'
      '\u098C\uE00C\u098F\uE00F\u0990\uE010\u0993\uE013\u0994\uE014'
      '\u0995\uE015\u0996\uE016\u0997\uE017\u0998\uE018\u0999\uE019'
      '\u099A\uE01A\u099B\uE01B\u099C\uE01C\u099D\uE01D\u099E\uE01E'
      '\u099F\uE01F\u09A0\uE020\u09A1\uE021\u09A2\uE022\u09A3\uE023'
      '\u09A4\uE024\u09A5\uE025\u09A6\uE026\u09A7\uE027\u09A8\uE028'
      '\u09AA\uE02A\u09AB\uE02B\u09AC\uE02C\u09AD\uE02D\u09AE\uE02E'
      '\u09AF\uE02F\u09B0\uE030\u09B2\uE032\u09B6\uE036\u09B7\uE037'
      '\u09B8\uE038\u09B9\uE039\u09BC\uE03C\u09BD\uE03D\u09BE\uE03E'
      '\u09BF\uE03F\u09C0\uE040\u09C1\uE041\u09C2\uE042\u09C3\uE043'
      '\u09C4\uE044\u09C7\uE047\u09C8\uE048\u09CB\uE04B\u09CC\uE04C'
      '\u09CD\uE04D\u09CE\uE083\u09D7\uE057\u09E0\uE060\u09E1\uE061'
      '\u09E2\uE062\u09E3\uE063\u09E6\uE066\u09E7\uE067\u09E8\uE068'
      '\u09E9\uE069\u09EA\uE06A\u09EB\uE06B\u09EC\uE06C\u09ED\uE06D'
      '\u09EE\uE06E\u09EF\uE06F\u09F0\uE071\u09F1\uE072\u09F2\uE073'
      '\u09F3\uE074\u09F4\uE075\u09F5\uE076\u09F6\uE077\u09F7\uE078'
      '\u09F8\uE079\u09F9\uE07A\u09FA\uE07B\u0964\uE064\u0965\uE065';

  /// দুই-অক্ষরের সংযুক্ত মাত্রা (NFD-পরবর্তী ধারায়ও আসতে পারে)।
  static const int _eSign = 0x09C7; // ে
  static const int _aaSign = 0x09BE; // া
  static const int _auLength = 0x09D7; // ৗ
  static const int _signO = 0xE04B;
  static const int _signAu = 0xE04C;

  static final Map<int, int> _table = _build();

  static Map<int, int> _build() {
    final m = <int, int>{};
    for (var i = 0; i + 1 < _pairs.length; i += 2) {
      m[_pairs.codeUnitAt(i)] = _pairs.codeUnitAt(i + 1);
    }
    return m;
  }

  /// টেস্ট/ডায়াগনস্টিক: টেবিলে কতটি এন্ট্রি আছে।
  static int get tableSize => _table.length;

  /// বাংলা টেক্সট → InterIndic কোড-পয়েন্টের স্ট্রিং।
  /// ম্যাপ না থাকা বাংলা অক্ষর বাদ যায় (বাংলা যেন কখনো আউটপুটে ফাঁস না করে);
  /// ASCII/স্পেস/যতিচিহ্ন অপরিবর্তিত থাকে।
  static String convert(String input) {
    final s = BengaliText.normalize(input);
    final out = StringBuffer();
    var i = 0;
    while (i < s.length) {
      final c = s.codeUnitAt(i);
      if (c == _eSign && i + 1 < s.length) {
        final n = s.codeUnitAt(i + 1);
        if (n == _aaSign) {
          out.writeCharCode(_signO);
          i += 2;
          continue;
        }
        if (n == _auLength) {
          out.writeCharCode(_signAu);
          i += 2;
          continue;
        }
      }
      final mapped = _table[c];
      if (mapped != null) {
        out.writeCharCode(mapped);
        i++;
        continue;
      }
      if (c >= 0x0980 && c <= 0x09FF) {
        i++; // অজানা বাংলা অক্ষর — বাদ (ফাঁস নয়)
        continue;
      }
      out.writeCharCode(c);
      i++;
    }
    return out.toString();
  }

  /// টেস্ট-গার্ড: টেবিলের নির্দিষ্ট জোড়া যাচাই (ম angl-নিরোধক রিগ্রেশন)।
  static bool mapsTo(int bengali, int interIndic) => _table[bengali] == interIndic;
}
