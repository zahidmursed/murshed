import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;

/// অফস্ক্রিন উইজেট → PNG (রিপোর্ট-ফরম PDF-এর জন্য)।
///
/// Flutter নিজেই বাংলা/আরবী/ইংরেজি সঠিকভাবে শেপ করে — তাই উইজেট-ছবি পথে
/// pdf প্যাকেজের শেপিং-সীমাবদ্ধতা (বাংলা যুক্তাক্ষর) প্রযোজ্য নয়।
class WidgetCapture {
  WidgetCapture._();

  /// [builder]-এর উইজেট নির্দিষ্ট [logicalWidth] প্রস্থে অফস্ক্রিন
  /// রেন্ডার করে [pixelRatio]× রেজোলিউশনে PNG দেয়।
  /// উচ্চতা কনটেন্ট-প্রাকৃতিক — A4-চেয়ে লম্বা হলেও পুরোটা ধরা হয়
  /// (OverflowBox দিয়ে উচ্চতা-বাউন্ড বাইপাস, কনটেন্ট কাটা হয় না)।
  static Future<Uint8List> capturePng({
    required OverlayState overlay,
    required WidgetBuilder builder,
    required double logicalWidth,
    double pixelRatio = 2.5,
    List<ImageProvider> warmupImages = const [],
  }) async {
    // ছবিগুলো আগেই ডিকোড — ক্যাপচারে ফাঁকা ঘর রোধ
    for (final provider in warmupImages) {
      try {
        await _decode(provider);
      } catch (_) {}
    }
    final boundaryKey = GlobalKey();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Material(
        type: MaterialType.transparency,
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: logicalWidth,
          maxWidth: logicalWidth,
          minHeight: 0,
          maxHeight: double.infinity,
          child: RepaintBoundary(key: boundaryKey, child: builder(_)),
        ),
      ),
    );
    overlay.insert(entry);
    try {
      // লেআউট + পেইন্ট স্থিতিশীল হওয়া পর্যন্ত ২ ফ্রেম অপেক্ষা
      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;
      final boundary = boundaryKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw StateError('উইজেট ক্যাপচার ব্যর্থ');
      }
      return data.buffer.asUint8List();
    } finally {
      entry.remove();
    }
  }

  /// context ছাড়া ইমেজ-ডিকোড (ImageStream listener — protected API এড়াতে)।
  static Future<ui.Image> _decode(ImageProvider provider) {
    final completer = Completer<ui.Image>();
    final stream = provider.resolve(const ImageConfiguration());
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        stream.removeListener(listener);
        if (!completer.isCompleted) completer.complete(info.image);
      },
      onError: (Object e, StackTrace? st) {
        stream.removeListener(listener);
        if (!completer.isCompleted) completer.completeError(e, st);
      },
    );
    stream.addListener(listener);
    return completer.future;
  }
}