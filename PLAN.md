# Dakhila Camera — প্রোজেক্ট বিশ্লেষণ ও পরিকল্পনা

> তৈরি: 2026-09-14 | Flutter 3.47.4 (stable) • Dart 3.13.3 • Android target

---

## ১. প্রোজেক্ট সারসংক্ষেপ

মাদ্রাসা শিক্ষার্থীদের ছবি তুলে **দাখিলা নম্বর দিয়ে সেভ** করার Flutter অ্যাপ
(যেমন `281.jpg`)। `assets/Data_basic.json` (≈1.6 MB, **1,431 জন** শিক্ষার্থী)
থেকে ডেটা প্রথম রানে SQLite-এ ইমপোর্ট হয়।

**কোর ফিচার:**
| ফিচার | অবস্থা |
|---|---|
| JSON → SQLite অটো ইমপোর্ট | ✅ কাজ করে |
| ক্লাস+ ফরিক নং ফিল্টার + All | ✅ কাজ করে |
| দাখিলা/নাম সার্চ | ⚠️ ডিবাউন্স নেই |
| Serial Mode (অটো next দাখিলা) | ⚠️ রিভিউ/রিটেক সুযোগ নেই |
| Passport Mode (431×531 crop) | ⚠️ main isolate-এ ভারী কাজ |
| Original Mode | ✅ কাজ করে |
| প্রগ্রেস (মোট/তোলা/বাকি) | ✅ কাজ করে |
| `flutter analyze` | ❌ 21টি info |
| `flutter test` | ✅ পাস (কিন্তু মাত্র ১টি টেস্ট) |

## ২. আর্কিটেকচার

```
lib/
├── main.dart                      → entry, Provider setup
├── models/student.dart            → Student model (fromJson/toMap)
├── db/database_helper.dart        → sqflite singleton, import/search/update
├── providers/student_provider.dart→ state: list, filter, search, modes, progress
└── screens/
    ├── list_screen.dart           → মূল লিস্ট, সার্চ, ফিল্টার, টগল
    └── camera_screen.dart         → ক্যামেরা, crop/resize, সেভ, serial advance
```

**Data flow:** `ListScreen` → `CameraScreen(student)` → `takePicture()` →
crop/resize (passport) → সেভ `Android/data/.../files/DakhilaCamera/{dakhila}.jpg` →
DB update (`is_captured=1`) → serial mode হলে `pushReplacement` পরের দাখিলায়।

**Stack:** flutter, camera ^0.10.5+9, sqflite, provider, image, path_provider

## ৩. শনাক্তকৃত সমস্যা

### A. বাগ / ঝুঁকি (অগ্রাধিকার-১)
1. **ক্যামেরা init ব্যর্থ হলে অ্যাপ আটকে যায়** — `_setupCamera()`-এ try/catch নেই;
   permission deny বা init error হলে infinite `CircularProgressIndicator`।
2. **`BuildContext` async gap-এ ব্যবহার** — `camera_screen.dart:64` (takePicture-এর
   *পরে* `Provider.of(context)`); widget unmount হলে crash। analyzer-ও ফ্ল্যাগ করেছে।
3. **সার্চে ডিবাউন্স নেই** — প্রতিটি কিস্ট্রোকে DB কোয়েরি; ধীর পুরনো কোয়েরি নতুন
   ফলাফল overwrite করার race condition।
4. **ফরিক পরিবর্তনে সার্চ হারিয়ে যায়** — `setForik()` → `load()` করলে সার্চবারের
   টেক্সট থাকলেও সার্চ আর apply হয় না।
5. **main isolate-এ ভারী কাজ** — 1.6 MB JSON decode + 1,431 insert (প্রথম রান) এবং
   প্রতি ছবিতে decode→crop→resize→encode → ফ্রিজ/ANR ঝুঁকি। `Isolate.run` দরকার।

### B. কোয়ালিটি (অগ্রাধিকার-২)
6. **21টি analyzer info** — মূলত `prefer_const_constructors` + `use_key_in_widget_constructors`।
7. **টেস্ট কভারেজ প্রায় শূন্য** — শুধু Student model; provider/DB/crop-এর কোনো টেস্ট নেই।
8. **`_takePicture()` monolith** — crop/save/DB/navigation সব এক ফাংশনে; pure
   `image_processor`-এ ভাগ করলে টেস্টযোগ্য হবে।
9. `forik_no`-তে index নেই (1,431 রোতে এখনও দ্রুত, তবে সস্তা অপটিমাইজেশন)।
10. **Git-এ এখনও কোনো commit নেই** (master branch empty)।
11. EXIF orientation bake করা হয় না (`image` প্যাকেজ) — নিরাপত্তার জন্য যোগ করা যায়।

### C. ফিচার গ্যাপ (অগ্রাধিকার-৩)
12. তোলা ছবির **preview / retake / delete** নেই — ভুল ছবি হলে আবার যেতে হয় ম্যানুয়ালি।
13. Serial mode সাথে সাথে advance করে — **review-র সুযোগ নেই** (ভুল ছবি আটকায় না)।
14. Front/back ক্যামেরা switch ও torch/flash নেই।
15. ছবি **export/share** সুবিধা নেই (README বলে File Manager দিয়ে কপি করতে হবে)।
16. JSON-এর বাড়তি ফিল্ড (MARHALA, EXAM_YEAR, ইংরেজি/আরবি নাম) DB-তে সেভ হয় না।
17. `applicationId = com.example.dakhila_camera` (placeholder) + release build
    debug key দিয়ে sign হচ্ছে।

## ৪. পরিকল্পনা (Phased Roadmap)

### Phase 1 — জরুরি বাগ ফিক্স (≈ আধা দিন) — ✅ সম্পন্ন (2026-09-14)
| # | কাজ | ফাইল |
|---|---|---|
| 1.1 | `_setupCamera()`-এ try/catch + permission/init error UI + "আবার চেষ্টা করুন" বাটন | camera_screen.dart |
| 1.2 | `await`-এর *আগে* provider capture করা; সব post-await `context`-এ `mounted` guard | camera_screen.dart |
| 1.3 | সার্চে 300ms debounce (Timer) + stale-result guard (request id) | list_screen.dart, student_provider.dart |
| 1.4 | `load()`-এ বর্তমান সার্চ কোয়েরি পুনঃপ্রয়োগ (ফরিক পরিবর্তনেও সার্চ থাকবে) | student_provider.dart |
| 1.5 | JSON import ও passport crop/encode → `Isolate.run()`-এ সরানো | database_helper.dart, camera_screen.dart |

**Validation:** `flutter analyze` (নতুন warning শূন্য) + আসল ডিভাইসে serial-mode
ফ্লো + প্রথম রানে ইমপোর্টের সময় UI freeze নেই।

### Phase 2 — রিফ্যাক্টর + টেস্ট (≈ ১ দিন) — ✅ সম্পন্ন (2026-09-14)

> **বাস্তবায়নের ফলাফল:** `flutter analyze` → No issues (২১টি info থেকে ০) •
> `flutter test` → ৯/৯ পাস (মডেল ×৪, image processor ×৪, sqflite_ffi DB ইন্টিগ্রেশন ×১) •
> প্রথম git commit সম্পন্ন। নতুন ফাইল: `lib/utils/image_processor.dart`,
> `test/image_processor_test.dart`, `test/db_test.dart`।
> নোট: `image` প্যাকেজ অবৈধ bytes-এ exception ছোড়ে — `processPassportBytes`
> try/catch দিয়ে null-চুক্তি রক্ষা করা হয়েছে।
| # | কাজ |
|---|---|
| 2.1 | `lib/utils/image_processor.dart`: pure ফাংশন `processPassport(bytes) → bytes` (crop math ইউনিট-টেস্টেবল) |
| 2.2 | 21টি lint ঠিক করা (const, key param) |
| 2.3 | টেস্ট যোগ: image_processor crop math, Student.fromJson edge case (null/int), provider logic (sqflite_common_ffi দিয়ে DB টেস্ট) |
| 2.4 | `forik_no`-তে index + (ঐচ্ছিক) schema v2: marhala/exam_year কলাম |
| 2.5 | **প্রথম git commit** (কাজ হারানোর ঝুঁকি বন্ধ) |

**Validation:** `flutter test` সবুজ + `flutter analyze` পরিষ্কার।

### Phase 3 — UX উন্নতি — ✅ 3A + 3B সম্পন্ন (2026-09-14), 3.5 ঐচ্ছিক বাকি

**3A — Review System** ✅ সম্পন্ন: Capture → Preview Screen (full image, zoom) →
[আবার তুলুন] [মুছুন] [পরের >] — ভুল ছবি সাথে সাথে ঠিক করা যায়; Delete = ফাইল +
রেকর্ড রিসেট করে একই শিক্ষার্থীর ক্যামেরায় ফেরত। লিস্টে thumbnail + full-screen
viewer-এও retake/delete আছে।

**3B — Camera Pro Controls** ✅ সম্পন্ন: Flash/Torch toggle, Front/Back switch,
3×3 Passport Grid Overlay (toggle বাটনসহ, `_GridPainter`), Pinch-to-Zoom
(init-এ `getMin/MaxZoomLevel` ক্যাশ → `setZoomLevel`, zoom indicator,
ডাবল-ট্যাপে zoom reset; zoom সাপোর্ট না থাকলে silently disable)।

> নতুন ফাইল: `lib/models/forik_stat.dart`, `lib/screens/review_screen.dart`,
> `lib/screens/image_viewer_screen.dart`। DB-তে `clearImage` + `getForikStats`
> (টেস্টে কভারড)। `flutter analyze` → 0 issues, `flutter test` → 9/9 পাস।

### Phase 3C — কাস্টমাইজ + ফিল্টার + স্টোরেজ — ✅ সম্পন্ন (2026-09-14)

- **কাস্টম ইমপোর্ট (JSON):** Settings screen (⚙️ AppBar-এ) — file_picker দিয়ে ডিভাইস
  থেকে JSON বাছাই → isolate-এ পার্স → transaction-এ পুরনো ডেটা রিপ্লেস; একই দাখিলার
  তোলা ছবির স্ট্যাটাস প্রিজার্ভ হয়। "ডাটা রিসেট" = সব মুছে বান্ডেল ডেটা পুনরায় লোড।
  (নতুন dep: file_picker 12.x — static `FilePicker.pickFiles()` API)
- **ক্লাস > ফরিক + All:** DB-তে `getDistinctClasses()` + `getForiksForClass()` —
  ক্লাস বাছলে ফরিক লিস্ট dynamic; সার্চ ও progress chips-ও ক্লাস মেনে চলে।
  "All" = ক্লাস+ফরিক দুটোই রিসেট। (hardcoded ১–১২ dropdown বাদ)
- **আউটপুট ফোল্ডার ওপেন:** Settings-এ সেভ পাথ দেখানো + [ফোল্ডার খুলুন] (DocumentsUI
  intent — android_intent_plus; ব্যর্থ হলে অটো পাথ-কপি) + [পাথ কপি] বাটন।

> নতুন টেস্ট: replaceAllStudents-এ ক্যাপচার প্রিজার্ভ, ক্লাস/ফরিক লিস্ট,
> রিসেট→বান্ডেল ডেটা পুনরুদ্ধার। `flutter analyze` → 0 issues, `flutter test` → 9/9 পাস।
| # | কাজ |
|---|---|
| 3.1 | লিস্টে তোলা ছবির thumbnail (Image.file) + full-screen viewer + delete |
| 3.2 | Serial mode: সেভের পর ছোট preview + **Next / Retake** বাটন (অথবা "review-then-advance" টগল) |
| 3.3 | Front/back ক্যামেরা switch + torch toggle |
| 3.4 | ফরিক-ভিত্তিক প্রগ্রেস (যেমন "ফরিক ৩: 40/120") |
| 3.5 | (ঐচ্ছিক) share_plus দিয়ে ছবি/ফোল্ডার share, বা MediaStore-এ Pictures/DakhilaCamera-তে কপি |

### Phase 4 — রিলিজ প্রস্তুতি (≈ আধা দিন)
| # | কাজ |
|---|---|
| 4.1 | applicationId rename (যেমন `com.madrasa.dakhila_camera`) + app icon |
| 4.2 | Release keystore + signing config (`key.properties` git-এ নয়) |
| 4.3 | `flutter build apk --release` + QA checklist (passport crop, serial advance, পুরনো ডেটা migrate) |
| 4.4 | README আপডেট (নতুন ফিচার, সাইনিং, রিলিজ প্রক্রিয়া) |

## ৫. সাজেশনকৃত কাজের ক্রম

```
Phase 1 (বাগ) → git commit → Phase 2 (রিফ্যাক্টর+টেস্ট) → git commit
→ Phase 3 (UX, প্রয়োজন অনুযায়ী বাছাই) → Phase 4 (রিলিজ)
```

প্রতিটি phase শেষে: `flutter analyze` + `flutter test` + ডিভাইসে ম্যানুয়াল ফ্লো টেস্ট।
