import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/foundation.dart';

/// অভিভাবকের মোবাইল থেকে কল ও হোয়াটসঅ্যাপ খোলার সহায়ক।
/// কল: সিস্টেম ডায়ালার (ACTION_DIAL — CALL_PHONE permission লাগে না,
/// ব্যবহারকারী নিজে কল বাটন চাপে)। হোয়াটসঅ্যাপ: wa.me লিংকে চ্যাট খোলে —
/// হোয়াটসঅ্যাপের ভয়েস-কল সরাসরি চালু করার কোনো পাবলিক API নেই, তাই
/// চ্যাট স্ক্রিনে নিয়ে যাওয়াই মানসম্মত উপায় (সেখানেই কল/মেসেজ বাটন আছে)।
class ContactHelper {
  ContactHelper._();

  /// যেকোনো ফরম্যাটের মোবাইলকে আন্তর্জাতিক ফরম্যাটে (8801XXXXXXXXX) নেয়।
  /// ফাঁকা/অবৈধ হলে null।
  static String? normalizeBdMobile(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return null;
    if (digits.startsWith('880') && digits.length >= 12) return digits;
    if (digits.startsWith('0')) return '880${digits.substring(1)}';
    return digits;
  }

  /// সিস্টেম ডায়ালারে নম্বর প্রি-ফিল করে। false = ডায়ালার খোলা যায়নি।
  static Future<bool> openDialer(String number) async {
    try {
      await AndroidIntent(
        action: 'android.intent.action.DIAL',
        data: 'tel:$number',
      ).launch();
      return true;
    } catch (e) {
      debugPrint('Dialer open failed: $e');
      return false;
    }
  }

  /// হোয়াটসঅ্যাপ চ্যাট খোলে (আন্তর্জাতিক নম্বর সহ)। false = খোলা যায়নি।
  static Future<bool> openWhatsAppChat(String intlNumber) async {
    try {
      await AndroidIntent(
        action: 'android.intent.action.VIEW',
        data: 'https://wa.me/$intlNumber',
      ).launch();
      return true;
    } catch (e) {
      debugPrint('WhatsApp open failed: $e');
      return false;
    }
  }
}