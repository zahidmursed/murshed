# Dakhila Camera v2.0 — উন্নত প্রোডাকশন প্ল্যান (বর্তমান অবস্থার ভিত্তিতে)

> বিশ্লেষণ: 2026-09-14 | **সংশোধিত স্ট্যাটাস: v1.2.0+4** | Target: v2.0 Production Ready
> ✅ **এটিই active প্ল্যান** — ব্যবহারকারীর সিদ্ধান্ত: applicationId চূড়ান্ত, keystore স্থগিত, icon পরে

---

## ১. বর্তমান অবস্থার SWOT বিশ্লেষণ

### ✅ Strengths (যা দারুণ করেছো)
- **0 analyze issue, 9 tests pass** — Phase 1 & 2 পুরোপুরি প্রফেশনাল
- **Isolate** দিয়ে ভারী কাজ (JSON import + image crop) — ANR সমস্যা সমাধান
- **Review System** (Phase 3A) — ভুল ছবির 90% সমস্যা শেষ
- **Custom JSON import + captured preserve** — বাস্তব মাঠে এটা সবচেয়ে দরকারি ফিচার
- **Class > Forik dynamic filter** — hardcoded 1-12 বাদ দেওয়া বুদ্ধিমানের কাজ

### ⚠️ Weaknesses (এখনই ঠিক করতে হবে)
1. **Storage Location ভুল**: `Android/data/.../files/` — Android 11+ এ File Manager দিয়ে খুঁজে পাওয়া কঠিন, User uninstall করলে সব ছবি মুছে যাবে। এটা **Critical**।
2. **applicationId = com.example...** — Play Store এ যাবে না, ফোনে 2টা অ্যাপ থাকলে clash করবে
3. **Debug-signed APK 53MB** — অনেক বড়, Release signed হলে 25MB হবে
4. ~~**Gallery তে দেখা যায় না**~~ ✅ v1.1.1-এ সমাধান — প্রতিটি ক্যাপচার MediaStore-এ যায়
5. **No Bulk Export** — 1431 ছবি একটা একটা করে কপি করা অসম্ভব, তোমার আগের v2.zip এ ZIP ছিল কিন্তু বর্তমান main branch এ নেই

### 🎯 Opportunity (তোমার Phase 5 থেকে সবচেয়ে লাভজনক 3টা)
- **PDF Print Sheet** — মাদ্রাসায় সবচেয়ে বেশি দরকার, প্রতিষ্ঠান এটার জন্য টাকা দেবে
- **Forik-wise ZIP + Missing Report** — অফিসের কাজ 1 ক্লিকে
- **Excel Import** — অনেক মাদ্রাসা JSON বোঝে না, Excel দেয়

---

## ২. নতুন আর্কিটেকচার (v2.0)

তোমার বর্তমান Structure ভালো, কিন্তু Scalable করতে:

```
lib/
├── core/
│   ├── constants.dart (passport size 600x800, quality 85)
│   ├── storage_paths.dart (centralized path logic - NEW)
│   └── result.dart (Success/Failure wrapper)
├── features/
│   ├── students/
│   │   ├── data/ (database_helper + models)
│   │   └── presentation/ (provider + list_screen)
│   ├── camera/ (camera_screen + review_screen)
│   └── export/ (export_service - ZIP, PDF, CSV) - NEW
├── services/
│   ├── media_store_service.dart (Gallery save)
│   └── file_service.dart (Folder open, safe delete with undo)
└── utils/
    ├── image_processor.dart (already good)
    └── excel_parser.dart (NEW)
```

**Key Decision:**
- Provider ই রাখো (Riverpod এ migrate করার দরকার নেই, সময় নষ্ট)
- `sqflite` ঠিক আছে, `drift` এ যাওয়ার দরকার নেই

---

## ৩. উন্নত রোডম্যাপ (Priority Order)

### Phase 4 - CRITICAL FIX (আজকেই করতে হবে, 4 ঘণ্টা) — v1.2.0

| # | কাজ | কেন Critical | ফাইল |
|---|---|---|---|
| 4.1 | **Storage Migration**: `getExternalStorageDirectory()` থেকে `MediaStore` / `Pictures/DakhilaCamera/` এ কপি + নতুন ছবি সরাসরি ওখানে সেভ | User data হারানোর ঝুঁকি | `media_store_service.dart` |
| 4.2 | **applicationId** change: `com.madrasa.dakhilacamera` | Play Store blocker | `build.gradle` |
| 4.3 | **Release Keystore**: `key.properties` + `signingConfig` | Debug APK বিতরণ করা অনিরাপদ | `android/` |
| 4.4 | **App Icon + Name**: `flutter_launcher_icons` দিয়ে বাংলা লোগো | প্রফেশনাল লুক | `pubspec.yaml` |
| 4.5 | **APK Size কমানো**: `shrinkResources true`, `minifyEnabled true`, `image` quality 90→85 | 53MB→~22MB | `build.gradle` |

**Validation:** Uninstall → Install → পুরনো ছবি Pictures এ আছে কিনা

**✅ Phase 4 ফলাফল (2026-09-14, v1.2.0+4):**
- 4.1 → risky flip না করে **dual-write + Settings-এ "সব ছবি গ্যালারিতে ব্যাকআপ" বাটন** (idempotent, progress সহ) — Pictures কপি uninstall-এও টিকে থাকে
- 4.2 ✅ applicationId = `com.madrasa.dakhilacamera` (namespace + MainActivity-ও সরানো হয়েছে) — **পুরনো ইনস্টলে আপডেট হবে না, fresh install লাগবে**
- 4.3 ⏳ স্থগিত (ব্যবহারকারীর সিদ্ধান্ত) — বহু ইউজার বিতরণের আগে অবশ্যই করতে হবে
- 4.4 ⏳ লোগো অপেক্ষমান — দিলে `flutter_launcher_icons` দিয়ে সেট হবে
- 4.5 ✅ split-per-abi + minify + shrinkResources: **arm64 18.5MB / armv7 16.2MB** (target <25MB পূরণ); JPEG quality 90 রাখা হয়েছে (প্রিন্ট কোয়ালিটি)

### Phase 5A - OFFICE SUPER FEATURES (আগামী 2 দিন) — v1.5.0 (Most Valuable)

| # | ফিচার | Implementation | Value |
|---|---|---|---|
| 5A.1 | **Forik-wise ZIP Export** | `archive` package - ফোল্ডার স্ট্রাকচার: `Class_Mishkat/Forik_1/281.jpg` | অফিস 1 ক্লিকে পাবে |
| 5A.2 | **Missing Report CSV** | `csv` package - `Dakhila, Name, Forik, Class` যাদের ছবি নেই | কোন ছাত্র বাদ পড়ল জানা যাবে |
| 5A.3 | **PDF Print Sheet** | `pdf` + `printing` package - A4 তে 12টা ছবি (3x4), নিচে দাখিলা + নাম | সরাসরি প্রিন্ট দিয়ে ID কার্ড বানানো |
| 5A.4 | **Gallery Grid View** | আলাদা ট্যাব "তোলা ছবি" - `GridView.builder` 100 pagination | দ্রুত ভেরিফিকেশন |

**Code Hint for ZIP:**
```dart
// export_service.dart
Future<String> exportForikWise({String? className}) async {
  // query all captured students
  // create zip with folders: ClassName/ForikNo/
  // also create missing.csv
}
```

### Phase 5B - QUICK WINS (1 দিন) — v1.6.0

| ফিচার | সময় |
|---|---|
| **Excel Import** (`excel` 4.x) | 3 ঘণ্টা - DAKHILA, STU_NAME কলাম ম্যাপ |
| **Dark Mode** (`ThemeMode` + `shared_preferences`) | 1 ঘণ্টা |
| **Settings Persist** (passport/serial/grid) | 30 মিনিট |
| **Undo Delete** (5 sec snackbar, temp file) | 1 ঘণ্টা |
| **Shutter Sound + Haptic** | 15 মিনিট |

### Phase 5C - QUALITY (1 দিন) — v1.7.0

- `integration_test`: import→capture→review→delete flow
- GitHub Actions: `flutter analyze` + `test` + APK build on push
- Pagination: ListView 100 করে lazy load (1431 জন একসাথে না)
- Thumbnail Cache: `LRU` 50 images in memory

### Phase 6 - PLAY STORE (1 দিন) — v2.0.0

- Screenshots (বাংলা), Privacy Policy (local data only)
- Internal Testing Track
- `appbundle` build: `flutter build appbundle`

---

## ৪. আগামী 3 দিনের Action Plan

**আজ (Day 1): Phase 4**
- [ ] media_store_service.dart বানাও, Pictures এ সেভ করো
- [ ] applicationId + icon + keystore
- [ ] `flutter build apk --release` → size check < 25MB

**কাল (Day 2): Phase 5A**
- [ ] ZIP Forik-wise + Missing CSV
- [ ] PDF Print Sheet (A4, 12 photos/page)

**পরশু (Day 3): Phase 5B**
- [ ] Excel Import
- [ ] Dark Mode + Settings persist

---

## ৫. যা করবে না (Avoid)

1. **Riverpod/Bloc এ migrate করবে না** — Provider যথেষ্ট, সময় নষ্ট
2. **Cloud Backup এখন না** — মাদ্রাসা offline চায়, privacy issue
3. **ML Kit Face Detection এখন না** — Phase 6 এর পর, 80% কাজে Grid ই যথেষ্ট
4. **Multi-tenant এখন না** — এক প্রতিষ্ঠানের অ্যাপ stable করো আগে

---

## ৬. Final Checklist for v2.0

- [ ] Pictures/DakhilaCamera তে সেভ হয়, Gallery তে দেখা যায়
- [ ] ZIP Export: Forik-wise folder + Missing CSV
- [ ] PDF Print: 12 photo/page
- [ ] Excel Import
- [ ] APK < 25MB, release signed, appId = com.madrasa.dakhilacamera
- [ ] Dark Mode + Undo Delete
- [ ] `flutter analyze` 0, `flutter test` 15+ tests

এই প্ল্যান অনুযায়ী v2.0 হবে অফিসের জন্য একদম প্রোডাকশন রেডি।
