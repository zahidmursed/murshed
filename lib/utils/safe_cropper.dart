import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:image_cropper/image_cropper.dart';

/// ImageCropper (uCrop)-এর নেটিভ দিকের দুটো পরিচিত সমস্যার বিরুদ্ধে নিরাপদ
/// মোড়ক — অ্যাপের সব ক্রপ-কল (review/viewer/scanner) এটার মধ্য দিয়ে যায়।
///
/// ১. **Double-reply ক্র্যাশ:** একটিই method-channel রিপ্লাই দুইবার জমা হলে
///    নেটিভ দিক `Reply already submitted` দিয়ে পুরো অ্যাপ ক্র্যাশ করে
///    (upstream issue #189; request=69, cancel-এ ফেটে)। MainActivity-র
///    `onActivityResult`-এ সেটা ক্যাচ করা হয়েছে; এখানে একসাথে **একটিই** ক্রপ
///    চালু রাখার নিয়ম — দ্বিতীয় ডাক সঙ্গে সঙ্গে null (বাতিল) দেয়, ফলে
///    ডাবল-স্টার্ট/ডাবল-রিপ্লাইয়ের সুযোগই তৈরি হয় না।
/// ২. **হারানো রিপ্লাই:** ক্রপ খোলা অবস্থায় activity recreate (রোটেশন/থিম
///    বদল) হলে নেটিভ রিপ্লাই নতুন delegate-এ পৌঁছায় না — Dart-এর Future
///    চিরকাল ঝুলে থাকে ও UI আটকে যেত। টাইমআউটে বাতিল (null) ধরে নেয়।
class SafeCropper {
  SafeCropper._();

  /// নেটিভ উত্তরের সর্বোচ্চ অপেক্ষা — সম্পূর্ণ লোকাল ক্রপ, ৫ মিনিট যথেষ্ট।
  static const Duration defaultTimeout = Duration(minutes: 5);

  /// চালু ক্রপের গার্ড-টোকেন; non-null মানে একটি ক্রপ এখনো ফেরত আসেনি।
  static Future<void>? _inFlight;

  /// [open]-কে চালায় ও তার ফল দেয়: CroppedFile (সফল) বা null
  /// (ইউজার বাতিল / টাইমআউট / অন্য ক্রপ ইতিমধ্যে চালু)। ব্যতিক্রম হলে
  /// সেটি সোজা প্রপাগেট করে — caller-এর try/catch স্বাভাবিকভাবে কাজ করে।
  static Future<CroppedFile?> crop(
    Future<CroppedFile?> Function() open, {
    Duration timeout = defaultTimeout,
  }) {
    if (_inFlight != null) {
      debugPrint('SafeCropper: ক্রপ ইতিমধ্যে চালু — দ্বিতীয় ডাক বাতিল ধরা হলো');
      return Future<CroppedFile?>.value(null);
    }
    final guard = Completer<void>();
    _inFlight = guard.future;
    return _guarded(open, timeout, guard);
  }

  static Future<CroppedFile?> _guarded(
    Future<CroppedFile?> Function() open,
    Duration timeout,
    Completer<void> guard,
  ) async {
    try {
      return await open().timeout(
        timeout,
        onTimeout: () {
          debugPrint(
              'SafeCropper: নেটিভ রিপ্লাই টাইমআউট (${timeout.inSeconds}s) — বাতিল ধরা হলো');
          return null;
        },
      );
    } finally {
      if (identical(_inFlight, guard.future)) _inFlight = null;
    }
  }

  @visibleForTesting
  static void debugReset() {
    _inFlight = null;
  }
}