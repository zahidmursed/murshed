import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// ডকুমেন্ট স্ক্যান-পরবর্তী ফিল্টার মোড।
enum DocumentFilterMode { original, magic, gray, bw }

/// চূড়ান্ত পাসপোর্ট ছবির নির্ধারিত মাপ।
const int passportWidth = 431;
const int passportHeight = 531;

enum PassportPreset { natural, fresh, bright }

extension PassportPresetLabel on PassportPreset {
  String get label => switch (this) {
        PassportPreset.natural => 'Natural',
        PassportPreset.fresh => 'Fresh',
        PassportPreset.bright => 'Bright',
      };
}

/// ছবির মাঝখান থেকে 431:531 অনুপাতে ক্রপ করে, হালকা auto-enhancement-সহ
/// 431×531 পিক্সেলে রিসাইজ করে।
/// Pure function — ইউনিট টেস্টযোগ্য।
img.Image processPassportImage(
  img.Image source, {
  PassportPreset preset = PassportPreset.fresh,
  bool enhance = true,
}) {
  // EXIF orientation থাকলে প্রয়োগ করা হয়
  final oriented = img.bakeOrientation(source);

  final int w = oriented.width;
  final int h = oriented.height;

  int targetW = w;
  int targetH = (targetW * passportHeight / passportWidth).round();
  if (targetH > h) {
    targetH = h;
    targetW = (targetH * passportWidth / passportHeight).round();
  }

  final int x = (w - targetW) ~/ 2;
  final int y = (h - targetH) ~/ 2;

  final cropped =
      img.copyCrop(oriented, x: x, y: y, width: targetW, height: targetH);
  final resized =
      img.copyResize(cropped, width: passportWidth, height: passportHeight);
  return enhance ? _autoEnhance(resized, preset) : resized;
}

/// ছোট (431×531) ছবিতে চলে বলে দ্রুত। দৃশ্যটি অন্ধকার হলে একটু বেশি উজ্জ্বল
/// করে; এরপর হালকা contrast/saturation ও highlight lift দেয়—ত্বকের রং বদলে
/// যাওয়ার মতো aggressive beauty filter ব্যবহার করা হয় না।
img.Image _autoEnhance(img.Image image, PassportPreset preset) {
  var luminanceTotal = 0.0;
  var samples = 0;
  // প্রতি 4 পিক্সেলে sample নেওয়ায় average নির্ণয় খুব দ্রুত হয়।
  for (var y = 0; y < image.height; y += 4) {
    for (var x = 0; x < image.width; x += 4) {
      final p = image.getPixel(x, y);
      luminanceTotal += 0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b;
      samples++;
    }
  }
  final average = luminanceTotal / samples;
  final baseBrightness = average < 90
      ? 1.14
      : average < 130
          ? 1.08
          : average < 170
              ? 1.04
              : 1.0;
  final (brightnessBoost, contrast, saturation, highlightLift) =
      switch (preset) {
    PassportPreset.natural => (0.0, 1.02, 1.01, 0.0),
    PassportPreset.fresh => (0.0, 1.06, 1.06, 0.04),
    PassportPreset.bright => (0.06, 1.08, 1.05, 0.06),
  };
  final brightness = baseBrightness + brightnessBoost;

  int color(double value) => value.round().clamp(0, 255);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final p = image.getPixel(x, y);
      // খুব হালকা contrast-এর জন্য RGB channel প্রস্তুত।
      var r = ((p.r - 128) * contrast + 128) * brightness;
      var g = ((p.g - 128) * contrast + 128) * brightness;
      var b = ((p.b - 128) * contrast + 128) * brightness;
      final luma = 0.2126 * r + 0.7152 * g + 0.0722 * b;
      // 6% saturation: fresh দেখায়, কিন্তু অতিরঞ্জিত হয় না।
      r = luma + (r - luma) * saturation;
      g = luma + (g - luma) * saturation;
      b = luma + (b - luma) * saturation;
      // উজ্জ্বল অংশে সামান্য soft highlight lift = subtle glossy finish।
      if (luma > 155 && highlightLift > 0) {
        r += (255 - r) * highlightLift;
        g += (255 - g) * highlightLift;
        b += (255 - b) * highlightLift;
      }
      image.setPixelRgba(x, y, color(r), color(g), color(b), p.a.toInt());
    }
  }
  return image;
}

/// JPEG bytes → passport-processed JPEG bytes (ডিকোড ব্যর্থ/অবৈধ হলে null)।
Uint8List? processPassportBytes(
  Uint8List bytes, [
  PassportPreset preset = PassportPreset.fresh,
  bool enhance = true,
]) {
  // image প্যাকেজের কিছু decoder অবৈধ input-এ exception ছোড়ে — null চুক্তি রক্ষা করতে
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    return null;
  }
  if (decoded == null) return null;
  return img.encodeJpg(
    processPassportImage(decoded, preset: preset, enhance: enhance),
    quality: 92,
  );
}

/// ভারী ডিকোড/ক্রপ/রিসাইজ/এনকোড কাজ main isolate-এর বাইরে চালায় (UI jank এড়াতে)।
Future<Uint8List?> processPassportInIsolate(
  Uint8List bytes, [
  PassportPreset preset = PassportPreset.fresh,
  bool enhance = true,
]) {
  return Isolate.run(() => processPassportBytes(bytes, preset, enhance));
}

/// ছবির আলো ও sharpness-এর হালকা পরীক্ষা। 0=ঠিক, 1=অন্ধকার, 2=blur,
/// 3=দুটোই। এটি সতর্কতা মাত্র; ছবি সেভ বন্ধ করে না।
int assessPhotoQualityBytes(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return 0;
  final preview = img.copyResize(decoded, width: 160);
  var light = 0.0;
  var edges = 0.0;
  var count = 0;
  for (var y = 1; y < preview.height; y += 2) {
    for (var x = 1; x < preview.width; x += 2) {
      final p = preview.getPixel(x, y);
      final left = preview.getPixel(x - 1, y);
      final up = preview.getPixel(x, y - 1);
      final luma = 0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b;
      final leftLuma = 0.2126 * left.r + 0.7152 * left.g + 0.0722 * left.b;
      final upLuma = 0.2126 * up.r + 0.7152 * up.g + 0.0722 * up.b;
      light += luma;
      edges += (luma - leftLuma).abs() + (luma - upLuma).abs();
      count++;
    }
  }
  if (count == 0) return 0;
  final dark = light / count < 55;
  final blurry = edges / count < 12;
  return (dark ? 1 : 0) | (blurry ? 2 : 0);
}

Future<int> assessPhotoQualityInIsolate(Uint8List bytes) =>
    Isolate.run(() => assessPhotoQualityBytes(bytes));

/// ছবিকে aspect-ratio ধরে রেখে সর্বোচ্চ [maxSide] পিক্সেলে রিসাইজ — isolate-এ।
/// আগে থেকেই ছোট হলে অপরিবর্তিত ছবি JPEG (quality 92) হিসেবে ফেরত দেয়।
/// ডিকোড ব্যর্থ হলে null।
Future<Uint8List?> resizeImageInIsolate(Uint8List bytes,
    {required int maxSide}) {
  return Isolate.run(() {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    // PNG সোর্স হলে PNG-ই ফেরত — এক্সটেনশন ও কনটেন্ট মিলবে
    final isPng = bytes.length > 8 && bytes[0] == 0x89 && bytes[1] == 0x50;
    final int w = decoded.width;
    final int h = decoded.height;
    final img.Image out;
    if (w <= maxSide && h <= maxSide) {
      out = decoded;
    } else {
      final double ratio = w >= h ? maxSide / w : maxSide / h;
      out = img.copyResize(decoded,
          width: (w * ratio).round(), height: (h * ratio).round());
    }
    return isPng ? img.encodePng(out) : img.encodeJpg(out, quality: 92);
  });
}

/// নেটিভ ক্রপ-এডিটরে (uCrop) দেওয়ার আগে সোর্স প্রস্তুত করে:
/// খুব বড় ছবি হলে সর্বোচ্চ [maxSide] বাহুতে নামিয়ে [destPath] (ASCII-নিরাপদ
/// অস্থায়ী ফাইল) এ JPEG লেখে — OOM ও ইউনিকোড-পাথ ক্র্যাশ এড়াতে।
/// রিটার্ন: destPath (ডিকোড ব্যর্থ হলে null)।
Future<String?> prepareCropSource({
  required String srcPath,
  required String destPath,
  int maxSide = 3000,
}) {
  return Isolate.run(() async {
    final bytes = await File(srcPath).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final int w = decoded.width;
    final int h = decoded.height;
    final img.Image out;
    if (w > maxSide || h > maxSide) {
      final double ratio = w >= h ? maxSide / w : maxSide / h;
      out = img.copyResize(decoded,
          width: (w * ratio).round(), height: (h * ratio).round());
    } else {
      out = decoded;
    }
    await File(destPath)
        .writeAsBytes(img.encodeJpg(out, quality: 95), flush: true);
    return destPath;
  });
}

/// স্ক্যান করা একাধিক পেজ উল্লম্বভাবে জোড়া হয়ে একটি JPEG দেয় (isolate-এ)।
/// প্রতিটি পেজ সবচেয়ে চওড়া পেজের মাপে রিসাইজ হয়; ডিকোড ব্যর্থ পেজ বাদ যায়।
Future<Uint8List?> mergePagesVerticallyInIsolate(List<Uint8List> pages) {
  return Isolate.run(() async {
    final decoded = <img.Image>[];
    for (final page in pages) {
      final d = img.decodeImage(page);
      if (d != null) decoded.add(d);
    }
    if (decoded.isEmpty) return null;
    final int maxW =
        decoded.map((d) => d.width).reduce((a, b) => a > b ? a : b);
    final heights = decoded
        .map((d) => (d.height * maxW / d.width).round())
        .toList(growable: false);
    final int totalH = heights.reduce((a, b) => a + b);
    var canvas = img.Image(width: maxW, height: totalH);
    var y = 0;
    for (var i = 0; i < decoded.length; i++) {
      final page = decoded[i];
      final scaled = heights[i] == page.height && maxW == page.width
          ? page
          : img.copyResize(page, width: maxW, height: heights[i]);
      canvas = img.compositeImage(canvas, scaled, dstX: 0, dstY: y);
      y += heights[i];
    }
    return img.encodeJpg(canvas, quality: 90);
  });
}

/// হিস্টোগ্রাম থেকে Otsu থ্রেশহোল্ড। প্লাটো (two-tone ছবিতে বিস্তৃত সমান
/// between-class) ক্ষেত্রে প্রথম মানে না আটকে প্লাটোর মাঝখান নেয় — নইলে
/// থ্রেশহোল্ড গাঢ় শিখরেই পড়ে গিয়ে হালকা ছায়াও কালো হয়ে যায়।
int _otsuFromHist(Int32List hist, int total) {
  var sum = 0;
  var cw = 0;
  var cs = 0;
  final cumW = Int64List(256);
  final cumS = Int64List(256);
  for (var i = 0; i < 256; i++) {
    sum += i * hist[i];
    cw += hist[i];
    cs += i * hist[i];
    cumW[i] = cw;
    cumS[i] = cs;
  }
  double betweenAt(int t) {
    final double wB = cumW[t].toDouble();
    if (wB <= 0 || wB >= total) return -1;
    final double wF = (total - wB).toDouble();
    final double mB = cumS[t] / wB;
    final double mF = (sum - cumS[t]) / wF;
    return wB * wF * (mB - mF) * (mB - mF);
  }

  var best = -1.0;
  var bestT = 128;
  for (var t = 0; t < 256; t++) {
    final b = betweenAt(t);
    if (b > best) {
      best = b;
      bestT = t;
    }
  }
  if (best <= 0) return bestT;
  // প্লাটো: best-এর ≥৯৯.৫% মানের বিস্তারের মাঝখান
  final double limit = best * 0.995;
  var lo = bestT, hi = bestT;
  for (var t = bestT - 1; t >= 0 && betweenAt(t) >= limit; t--) {
    lo = t;
  }
  for (var t = bestT + 1; t < 256 && betweenAt(t) >= limit; t++) {
    hi = t;
  }
  return (lo + hi) ~/ 2;
}

/// CamScanner-স্টাইল magic ফিল্টার (isolate-এ চলে):
/// ১) illumination map — মোটা গ্রিডে সেল-প্রতি "কাগজের উজ্জ্বলতা" (৯০তম
///    পার্সেন্টাইল — লেখার কালচে যেন মানচিত্র নষ্ট না করে), ৩×৩ মসৃণ করে;
/// ২) মূল ছবি ÷ illumination map → ছায়া/আলোর গ্রেডিয়েন্ট কেটে কাগজ সমান সাদা;
/// ৩) সাদা-বিন্দু গেইন (৯২তম পার্সেন্টাইলকে ২৫৫-এ তোলা) + হালকা saturation।
img.Image _magicColor(img.Image image) {
  final int w = image.width;
  final int h = image.height;

  // --- ধাপ ১: illumination grid ---
  const int cellTarget = 48;
  final int gw = math.max(2, (w / cellTarget).ceil());
  final int gh = math.max(2, (h / cellTarget).ceil());
  final int cells = gw * gh;
  final hist = Int32List(cells * 256);
  final sumR = Float64List(cells);
  final sumG = Float64List(cells);
  final sumB = Float64List(cells);
  final sumL = Float64List(cells);
  final cnt = Int32List(cells);
  for (var y = 0; y < h; y++) {
    final int gy = math.min(gh - 1, y * gh ~/ h);
    for (var x = 0; x < w; x += 2) {
      final int gx = math.min(gw - 1, x * gw ~/ w);
      final int c = gy * gw + gx;
      final p = image.getPixel(x, y);
      final double r = p.r.toDouble();
      final double g = p.g.toDouble();
      final double b = p.b.toDouble();
      final double l = 0.2126 * r + 0.7152 * g + 0.0722 * b;
      hist[c * 256 + l.round().clamp(0, 255)]++;
      sumR[c] += r;
      sumG[c] += g;
      sumB[c] += b;
      sumL[c] += l;
      cnt[c]++;
    }
  }
  var illR = Float64List(cells);
  var illG = Float64List(cells);
  var illB = Float64List(cells);
  for (var c = 0; c < cells; c++) {
    final int n = math.max(1, cnt[c]);
    final int target = (n * 0.90).round();
    var acc = 0;
    var paper = 240.0;
    for (var v = 0; v < 256; v++) {
      acc += hist[c * 256 + v];
      if (acc >= target) {
        paper = v.toDouble();
        break;
      }
    }
    // চ্যানেল-অনুপাত ধরে রাখলে ছায়ার রঙ-ছায়াও (color cast) কেটে যায়
    final double mL = math.max(1.0, sumL[c] / n);
    final double scale = paper / mL;
    illR[c] = math.min(255.0, sumR[c] / n * scale);
    illG[c] = math.min(255.0, sumG[c] / n * scale);
    illB[c] = math.min(255.0, sumB[c] / n * scale);
  }
  // সেল-সীমার খাঁজ এড়াতে ১ দফা ৩×৩ মসৃণকরণ
  illR = _boxSmooth(illR, gw, gh);
  illG = _boxSmooth(illG, gw, gh);
  illB = _boxSmooth(illB, gw, gh);

  final illumSmall = img.Image(width: gw, height: gh);
  for (var cy = 0; cy < gh; cy++) {
    for (var cx = 0; cx < gw; cx++) {
      final int c = cy * gw + cx;
      illumSmall.setPixelRgba(cx, cy, illR[c].round().clamp(0, 255),
          illG[c].round().clamp(0, 255), illB[c].round().clamp(0, 255), 255);
    }
  }
  // ছোট মানচিত্র বিলিয়ার-আপস্কেল — পিক্সেল-প্রতি মসৃণ illumination মান
  final illum = img.copyResize(illumSmall,
      width: w, height: h, interpolation: img.Interpolation.linear);


  // --- ধাপ ২: ভাগ (মূল ÷ আলো) ---
  final divided = Uint8List(w * h * 3);
  final lumHist = Int32List(256);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = image.getPixel(x, y);
      final q = illum.getPixel(x, y);
      final int di = (y * w + x) * 3;
      final double qr = math.max(30.0, q.r.toDouble());
      final double qg = math.max(30.0, q.g.toDouble());
      final double qb = math.max(30.0, q.b.toDouble());
      final int dr = (p.r.toDouble() * 255.0 / qr).round().clamp(0, 255);
      final int dg = (p.g.toDouble() * 255.0 / qg).round().clamp(0, 255);
      final int db = (p.b.toDouble() * 255.0 / qb).round().clamp(0, 255);
      divided[di] = dr;
      divided[di + 1] = dg;
      divided[di + 2] = db;
      lumHist[(0.2126 * dr + 0.7152 * dg + 0.0722 * db).round().clamp(0, 255)]++;
    }
  }

  // --- ধাপ ৩: সাদা-বিন্দু গেইন + হালকা saturation ---
  final int total = w * h;
  final int target = (total * 0.92).round();
  var acc = 0;
  var paperLevel = 255;
  for (var v = 0; v < 256; v++) {
    acc += lumHist[v];
    if (acc >= target) {
      paperLevel = v;
      break;
    }
  }
  final double gain =
      (255.0 / math.max(120.0, paperLevel.toDouble())).clamp(1.0, 1.35);
  const double sat = 1.06;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final int di = (y * w + x) * 3;
      final double r = divided[di] * gain;
      final double g = divided[di + 1] * gain;
      final double b = divided[di + 2] * gain;
      final double luma = 0.2126 * r + 0.7152 * g + 0.0722 * b;
      final int rr = (luma + (r - luma) * sat).round().clamp(0, 255);
      final int gg = (luma + (g - luma) * sat).round().clamp(0, 255);
      final int bb = (luma + (b - luma) * sat).round().clamp(0, 255);
      image.setPixelRgba(x, y, rr, gg, bb, 255);
    }
  }
  return image;
}

/// ছোট গ্রিডে ১ দফা ৩×৩ বক্স-মসৃণকরণ (নতুন অ্যারে ফেরত দেয়)।
Float64List _boxSmooth(Float64List grid, int gw, int gh) {
  final tmp = Float64List(grid.length);
  for (var y = 0; y < gh; y++) {
    for (var x = 0; x < gw; x++) {
      final int xa = math.max(0, x - 1);
      final int xb = math.min(gw - 1, x + 1);
      tmp[y * gw + x] =
          (grid[y * gw + xa] + grid[y * gw + x] + grid[y * gw + xb]) / 3.0;
    }
  }
  final out = Float64List(grid.length);
  for (var y = 0; y < gh; y++) {
    final int ya = math.max(0, y - 1);
    final int yb = math.min(gh - 1, y + 1);
    for (var x = 0; x < gw; x++) {
      out[y * gw + x] =
          (tmp[ya * gw + x] + tmp[y * gw + x] + tmp[yb * gw + x]) / 3.0;
    }
  }
  return out;
}

/// CamScanner-স্টাইল adaptive B&W (isolate-এ):
/// Sauvola লোকাল থ্রেশহোল্ড (স্লাইডিং-উইন্ডো, O(w·h) সময় / O(w) মেমোরি) —
/// ছায়া-গ্রেডিয়েন্টেও লেখা টিকিয়ে রাখে; সাথে প্লাটো-সংশোধিত গ্লোবাল Otsu-র
/// ৫৫% ফ্লোর — নইলে বড় গাঢ় অংশ (সিল/ছবি) সাদা হয়ে যেত।
img.Image _adaptiveBinarize(img.Image image) {
  final int w = image.width;
  final int h = image.height;
  final gray = Uint8List(w * h);
  final hist = Int32List(256);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = image.getPixel(x, y);
      final int l =
          (0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b).round().clamp(0, 255);
      gray[y * w + x] = l;
      hist[l]++;
    }
  }
  final double floor = _otsuFromHist(hist, w * h) * 0.55;

  const double k = 0.2;
  const double rMax = 128.0;
  var win = (math.min(w, h) ~/ 30).clamp(25, 61);
  if (win.isEven) win++;
  final int rad = win ~/ 2;

  // উল্লম্ব উইন্ডো: রিং-বাফারে সারি-প্রতি মান রেখে কলাম-যোগ হালনাগাদ
  final colSum = Float64List(w);
  final colSumSq = Float64List(w);
  final ring = List.generate(win, (_) => Float64List(w), growable: false);
  final ringSq = List.generate(win, (_) => Float64List(w), growable: false);

  for (var y = 0; y < h; y++) {
    final int ri = y % win;
    final row = ring[ri];
    final rowSq = ringSq[ri];
    for (var x = 0; x < w; x++) {
      final double v = gray[y * w + x].toDouble();
      colSum[x] += v - row[x]; // পুরনো রো-মান বাদ, নতুনটা যোগ
      colSumSq[x] += v * v - rowSq[x];
      row[x] = v;
      rowSq[x] = v * v;
    }
    // অনুভূমিক উইন্ডো: স্লাইডিং যোগ — T = m·(1 − k·(1 − s/R))
    final int rowsIn = math.min(y + 1, win); // উল্লম্ব উইন্ডোতে সারি-সংখ্যা
    double wSum = 0, wSumSq = 0;
    int cnt = 0, left = 0, right = -1;
    for (var x = 0; x < w; x++) {
      final int nr = math.min(x + rad, w - 1);
      while (right < nr) {
        right++;
        wSum += colSum[right];
        wSumSq += colSumSq[right];
        cnt++;
      }
      final int nl = math.max(x - rad, 0);
      while (left < nl) {
        wSum -= colSum[left];
        wSumSq -= colSumSq[left];
        cnt--;
        left++;
      }
      final double n = (cnt * rowsIn).toDouble();
      final double m = wSum / n;
      final double varr = math.max(0.0, wSumSq / n - m * m);
      final double sd = math.sqrt(varr);
      var t = m * (1 - k * (1 - sd / rMax));
      if (t < floor) t = floor;
      final int out = gray[y * w + x] > t ? 255 : 0;
      image.setPixelRgba(x, y, out, out, out, 255);
    }
  }
  return image;
}

/// ডকুমেন্ট ফিল্টার (isolate-এ):
/// original = অপরিবর্তিত; magic = ছায়া-আলো মুক্ত (illumination ভাগ);
/// gray = সাদাকালো; bw = adaptive বাইনারাইজ (Sauvola + Otsu-ফ্লোর)।
/// ডিকোড ব্যর্থ হলে null।
Future<Uint8List?> enhanceDocumentInIsolate(
    Uint8List bytes, DocumentFilterMode mode) {
  return Isolate.run(() {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    switch (mode) {
      case DocumentFilterMode.original:
        return bytes;
      case DocumentFilterMode.gray:
        return img.encodeJpg(img.grayscale(decoded), quality: 88);
      case DocumentFilterMode.bw:
        return img.encodeJpg(_adaptiveBinarize(decoded), quality: 88);
      case DocumentFilterMode.magic:
        return img.encodeJpg(_magicColor(decoded), quality: 90);
    }
  });
}

/// ছবির লম্বা বাহু [maxSide]-এর বেশি হলে ছোট করে JPEG ফেরত দেয় (isolate-এ)।
/// ডিকোড ব্যর্থ হলে null।
Future<Uint8List?> limitLongSideInIsolate(Uint8List bytes,
    {required int maxSide}) {
  return Isolate.run(() {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final int w = decoded.width;
    final int h = decoded.height;
    if (w <= maxSide && h <= maxSide) return img.encodeJpg(decoded, quality: 90);
    final double ratio = w >= h ? maxSide / w : maxSide / h;
    final resized = img.copyResize(decoded,
        width: (w * ratio).round(), height: (h * ratio).round());
    return img.encodeJpg(resized, quality: 90);
  });
}
