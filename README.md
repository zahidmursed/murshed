# Dakhila Camera 📸

মাদরাসা/প্রতিষ্ঠানের শিক্ষার্থীদের ছবি তুলে **দাখিলা নম্বর দিয়ে অটো-সেভ** করার
Flutter অ্যাপ — যেমন `281.jpg`। প্রতিষ্ঠানের নিজস্ব ডেটা (JSON) ইমপোর্ট করে
ক্লাস/ফরিক ধরে সবার ছবি গোছানো যায়, কে বাদ পড়ল তা এক নজরে দেখা যায়।

**বর্তমান ভার্সন:** 2.0.0+15 • Flutter 3.47 • টার্গেট: Android • ইন্টারনেট লাগে না

---

## ✨ বর্তমান বৈশিষ্ট্য ও কার্যকারিতা

### 📂 ডাটা ম্যানেজমেন্ট (⚙️ সেটিংস)
- **বান্ডেল ডেটা অটো-লোড** — প্রথম রানে `assets/Data_basic.json` (১,৪৩১ রেকর্ড)
  SQLite-এ ইমপোর্ট হয় (ব্যাকগ্রাউন্ড isolate-এ, UI ফ্রিজ হয় না)
- **কাস্টম JSON ইমপোর্ট** — ডিভাইস থেকে নিজের JSON ফাইল বেছে নিয়ে পুরনো ডেটার
  বদলে বসানো যায়; **একই দাখিলার তোলা ছবির হিসাব প্রিজার্ভ** থাকে
- **কাস্টম Excel ইমপোর্ট (.xlsx)** — হেডার কেস-ইনসেনসিটিভ (DAKHILA, STU_NAME,
  CLASS_NAME, FORIK_NO, FATHER_NAME, DAKHILA_YEAR); isolate-এ পার্স
- **ডার্ক মোড** — সিস্টেম/লাইট/ডার্ক (সেটিংসে)
- **সেটিংস মনে থাকে** — passport/serial/grid মোড ও থিম পরের বারও
- **ডাটা রিসেট** — confirm দিলে সব মুছে বান্ডেল ডেটা আবার লোড
- ডেটা ডিভাইসেই থাকে (SQLite) — কোথাও আপলোড হয় না

### 🔍 ফিল্টার ও সার্চ
- **ক্লাস > ফরিক** দুই-স্তরের ফিল্টার (দুটোই ডেটা থেকে dynamic) + **All** রিসেট
- দাখিলা/নাম দিয়ে **সার্চ** (300ms debounce — প্রতি কিস্ট্রোকে DB চাপে না)
- **প্রগ্রেস chips**: `ফরিক ১: 12/119` — সবুজ (সম্পূর্ণ) / কমলা (চলমান); ট্যাপ = ফিল্টার
- হেডারে **মোট / তোলা / বাকি** লাইভ স্ট্যাট

### 📸 ক্যামেরা
- **Passport Mode** — মাঝখান থেকে 431:531 অনুপাতে ক্রপ করে **431×531** JPEG (quality 92), হালকা auto brightness/contrast/fresh enhancement
- **Original Mode** — যেমন তোলা তেমন সেভ
- **Serial Mode** — ছবি সেভ হলে স্বয়ংক্রিয়ভাবে পরের দাখিলার প্রস্তাব
- **Review Screen** — সেভের পর full-screen প্রিভিউ: [আবার তুলুন] [মুছুন] [পরের >]
  — ভুল ছবি সাথে সাথে ধরা পড়ে ও ঠিক হয়
- **Pro controls** — front/back switch, torch, **3×3 গ্রিড overlay** (টগলেবল),
  **pinch-to-zoom** + ডাবল-ট্যাপে reset + zoom indicator
- **ক্যাপচার ফিডব্যাক** — হ্যাপটিক + শাটার সাউন্ড
- ভারী ইমেজ প্রসেসিং (crop/resize) ব্যাকগ্রাউন্ড isolate-এ — ক্যামেরা আটকায় না
- permission/init সমস্যায় বাংলা error message + "আবার চেষ্টা করুন" বাটন

### 🗃 ছবি ম্যানেজমেন্ট
- লিস্টে তোলা ছবির **thumbnail**; ট্যাপ করলে **full-screen viewer** (zoom সহ)
- viewer থেকেই **retake / delete** — delete-এ ফাইল ও রেকর্ড দুটোই রিসেট হয়
- **Undo delete** — মোছার পর ৫ সেকেন্ডে "পুনরুদ্ধার" স্ন্যাকবার
- AppBar-এ 🖼 আইকনে **ছবি গ্যালারি গ্রিড** — শুধু তোলা ছবি, দ্রুত ভেরিফিকেশন

### 📤 এক্সপোর্ট (AppBar-এ 🗜 আইকন) — v2, doc-aware
- **ZIP এক্সপোর্ট v2** — ছাত্র-প্রতি ফোল্ডারের ভিতরে **PHOTO/BIRTH/FORM** সাবফোল্ডারে সব ডক
  (`ক্লাস/ফরিক/দাখিলা_নাম/PHOTO/281.jpg`, `BIRTH/281.jpg`, ...) + `_reports/missing.csv` + `_reports/summary.txt`;
  streaming encoder — হাজার ফাইলেও মেমোরি নিরাপদ
- **Status Report (CSV)** — প্রতি ছাত্রের Photo/Birth/Form yes/no + MissingCount
  (UTF-8 BOM, Excel-এ বাংলা ঠিক দেখায়)
- **PDF প্রিন্ট শিট** — A4-তে ৯টি করে (3×3) পাসপোর্ট ছবি + দাখিলা নম্বর ক্যাপশন
- এক্সপোর্ট শেষে সরাসরি **শেয়ার শিট** খোলে (WhatsApp/Gmail/PC)
- স্কোপ = মূল লিস্টের বর্তমান ক্লাস/ফরিক ফিল্টার

### 📚 3-Document System (Phase 6+7+8 — v1.9.0)
- **একজন ছাত্র = ৩টি স্লট**: 📷 PHOTO • 📜 BIRTH (জন্মসনদ) • 📝 FORM (আবেদন ফরম)
- লিস্টে **৩-ডট ইনডিকেটর** ●●○ + `x/3 ডক` প্রগ্রেস (সবুজ = সম্পন্ন); ট্যাপে
  **Document Dashboard** — progress ring + ৩টি কার্ড
- **PHOTO কার্ড**: ক্যামেরা (v2 ফোল্ডারে সেভ) + দেখুন + মুছুন
- **BIRTH কার্ড**: শুধু **JPEG/PNG** ফাইল (PDF নয়) + দেখুন + মুছুন
- **FORM কার্ড**: PDF/JPG/PNG ফাইল + দেখুন (system viewer) + মুছুন
- **Bulk ইমপোর্ট** (⚙️ সেটিংসে): একসাথে অনেক ফাইল — নাম `দাখিলা_টাইপ.ext`
  (যেমন `281_BIRTH.pdf`) হলে auto assign
- DB **v4**: `documents` টেবিল (UNIQUE(dakhila, doc_type)) + `students`-এ
  `marhala`/`exam_year`/`total_docs` কলাম — পুরনো ছবি অটো-মাইগ্রেট (copy-not-move)
- `services/storage_service.dart` — ছাত্র-প্রতি ফোল্ডার লেআউট
  `DakhilaCamera/v2/<ক্লাস>/Forik_N/<দাখিলা>/<PHOTO|BIRTH|FORM>/`; ⚙️ সেটিংসে **"স্টোরেজ সাজান"** বাটনে
  পুরনো flat ছবি নতুন লেআউটে মাইগ্রেট
- Document Scanner (ML Kit edge-detect) — পরের ধাপে

### 💾 স্টোরেজ
- সেভ হয়: `Android/data/com.madrasa.dakhilacamera/files/DakhilaCamera/{দাখিলা}.jpg`
- **গ্যালারিতেও সেভ** — ফোনের গ্যালারির `Pictures/DakhilaCamera`-তেও যায় (MediaStore);
  retake-এ replace হয়, delete-এ গ্যালারি কপিও মুছে যায় (Android 10+ permission-মুক্ত)
- **গ্যালারি ব্যাকআপ বাটন** — ⚙️ সেটিংসে "সব ছবি গ্যালারিতে ব্যাকআপ" (পুরনো ছবিগুলো এক ক্লিকে, বারবার চালানো নিরাপদ)
- **পুরনো ছবি রিকভারি** — ⚙️ সেটিংসে: fresh install/আপডেটের পর গ্যালারির `Pictures/DakhilaCamera` কপি থেকে দাখিলা নম্বর মিলিয়ে তোলা ছবি ফিরিয়ে আনে (storage permission সহ)
- ⚙️ সেটিংসে **[ফোল্ডার খুলুন]** (সিস্টেম ফাইল ম্যানেজার) + **[পাথ কপি]** ফলব্যাক
- শুধু CAMERA permission; ছবি/ডেটা কোথাও পাঠানো হয় না

## 🚀 সেটআপ ও বিল্ড

প্রয়োজন: Flutter SDK (নতুন stable), Android SDK, JDK 17 (Android Studio-র bundled
JBR চলে)। টুলস যাচাই: `flutter doctor`।

```bash
flutter pub get              # dependencies
flutter run                  # ডিভাইস/এমুলেটরে চালান
flutter test                 # ইউনিট টেস্ট (৯টি)
flutter analyze              # 0 issues থাকা উচিত
flutter build apk --release  # APK তৈরি (universal)
flutter build apk --release --split-per-abi  # ছোট APK (ABI অনুযায়ী আলাদা, ~16-20MB)
```

- রেডিমেড **release-signed** বিল্ড (রিপো রুটে): `DakhilaCamera-v2.0.0-arm64-release.apk`
  (~20.3MB, আধুনিক ফোন), `DakhilaCamera-v2.0.0-armv7-release.apk` (পুরনো ফোন),
  `DakhilaCamera-v2.0.0-release.aab` (Play Store-এর জন্য) — keystore: `android/key/`
- Windows-এ Kotlin cache lock error এলে দেখুন: `android/gradle.properties`-এ
  `kotlin.incremental=false` (এই প্রোজেক্টে সেট করা আছে)

## 📱 দ্রুত ব্যবহার নির্দেশিকা

1. ⚙️ → **JSON ফাইল থেকে ডাটা ইমপোর্ট** দিয়ে নিজের ডেটা বসান (না হলে বান্ডেল ডেটা চলবে)
2. লিস্টে **ক্লাস > ফরিক** বাছুন — প্রগ্রেস chip-এ দেখুন কতজন তোলা/বাকি
3. ছবির আইকনে ট্যাপ → ক্যামেরা → (দরকার হলে গ্রিড/টর্চ/zoom) → 📸 চাপুন
4. Review-তে ছবি ঠিক আছে? → **পরের >** ; ভুল? → **আবার তুলুন** বা **মুছুন**
5. শেষে ⚙️ → **ফোল্ডার খুলুন** — সব ছবি পাবেন `দাখিলা.jpg` নামে

## 🗂 প্রোজেক্ট স্ট্রাকচার

```
lib/
├── main.dart                    # entry + Provider setup
├── models/
│   ├── student.dart             # Student model + JSON→DB mapping
│   └── forik_stat.dart          # ফরিকভিত্তিক প্রগ্রেস স্ট্যাট
├── db/
│   └── database_helper.dart     # sqflite: import/filter/search/reset/replace
├── providers/
│   └── student_provider.dart    # state: লিস্ট, ফিল্টার, সার্চ(debounce), মোড
├── screens/
│   ├── list_screen.dart         # মূল লিস্ট + ফিল্টার + প্রগ্রেস
│   ├── camera_screen.dart       # ক্যামেরা + pro controls
│   ├── review_screen.dart       # সেভ-পরবর্তী রিভিউ (retake/delete/next)
│   ├── image_viewer_screen.dart # full-screen viewer + delete
│   └── settings_screen.dart     # ইমপোর্ট/রিসেট/ফোল্ডার
└── utils/
    └── image_processor.dart     # passport crop/resize (pure, isolate-safe)
```

## 🧪 টেস্ট ও কোয়ালিটি

| চেক | অবস্থা |
|---|---|
| `flutter analyze` | 0 issues |
| `flutter test` | ৯/৯ পাস — model, image_processor, DB-integration (sqflite_common_ffi) |
| git | ফিচারভিত্তিক commit, clean tree |

## 🛠 টেক স্ট্যাক

| প্যাকেজ | কাজ |
|---|---|
| camera 0.10.6 | প্রিভিউ / ক্যাপচার / torch / zoom |
| sqflite + path | SQLite ডেটাবেস |
| provider | state management |
| image | passport crop/resize (isolate-এ) |
| file_picker 12 | কাস্টম JSON ইমপোর্ট |
| android_intent_plus | ফোল্ডার ওপেন intent |
| path_provider | সেভ ডিরেক্টরি |

## 🔮 ভবিষ্যৎ পরিকল্পনা (Roadmap)

বিস্তারিত ব্যাকলগ: `PLAN.md` → **Phase 5**। মূল আইডিয়া:

**কাছাকাছি (quick wins)**
- Excel/CSV ইমপোর্ট • ডার্ক মোড • ক্যাপচারে সাউন্ড/ভাইব্রেশন • মোছা ছবি Undo • মোড-সেটিংস মনে রাখা

**মাঝারি**
- ✅ PDF শিট, ZIP export + missing রিপোর্ট, গ্যালারি গ্রিড ভিউ (v1.5.0 — Phase 5A)
- মারহালা/বছর ভিত্তিক ডেটা (schema v3) • integration test + CI (GitHub Actions)

**দূরবর্তী**
- মুখ শনাক্ত করে auto-crop assist • ক্লাউড ব্যাকআপ • ট্যাবলেট লেআউট
- Play Store রিলিজ (keystore + applicationId + app icon)

## ⚠️ নোট

- বর্তমান APK **debug key**-এ signed — টেস্ট/সরাসরি ইনস্টলের জন্য; Play Store-এর জন্য নয়
- ✅ v1.2.0 থেকে applicationId = `com.madrasa.dakhilacamera` — **পুরনো (v1.1.x) ইনস্টলের
  উপর আপডেট হবে না, fresh install লাগবে**; আগের ছবিগুলো গ্যালারিতে থেকে যাবে
- বাংলা ফন্ট ডিফল্টভাবে ঠিক দেখায়; ডেটার নামগুলো Unicode বাংলা হতে হবে
