import 'package:shared_preferences/shared_preferences.dart';

/// কেস নোট-এর PIN সুরক্ষা (স্তর: নোট সিস্টেম)।
/// - PIN সরাসরি সংরক্ষিত হয় না — hash (FNV-1a-ঘরানার) সংরক্ষিত হয়
/// - একবার আনলক করলে সেশন জুড়ে খোলা থাকে (অ্যাপ বন্ধ করলে আবার পিন লাগবে)
/// - লোকাল ডিটারেন্স হিসেবে যথেষ্ট; ক্রিপ্টো-গ্রেড সুরক্ষা নয়
class CaseNotesService {
  CaseNotesService._();

  static const String _pinKey = 'caseNotesPinHash';
  static bool _unlocked = false;

  static bool get isUnlocked => _unlocked;

  static void unlock() => _unlocked = true;

  static void lock() => _unlocked = false;

  /// সাধারণ FNV-1a-ঘরানার হ্যাশ — ৮-অক্ষর hex।
  static String hashPin(String pin) {
    var h = 0x811c9dc5;
    for (final code in pin.codeUnits) {
      h ^= code;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }

  /// পিন সেট করা আছে কিনা।
  static Future<bool> isPinSet() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_pinKey);
    return v != null && v.isNotEmpty;
  }

  /// পিন মিলছে কিনা।
  static Future<bool> verifyPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_pinKey) == hashPin(pin);
  }

  /// পিন সেট/পরিবর্তন (সেট করলেই সেশন আনলক)।
  static Future<void> setPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pinKey, hashPin(pin));
    _unlocked = true;
  }

  /// পিন সরানো (লক বন্ধ)।
  static Future<void> removePin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pinKey);
    _unlocked = false;
  }
}
