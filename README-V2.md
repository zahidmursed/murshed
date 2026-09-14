# Dakhila Camera 📸 — v1.7.0 (Phase 5B Complete) → v2.0 3-Document

মাদরাসা/প্রতিষ্ঠানের শিক্ষার্থীদের **৩টি ডকুমেন্ট** — (1) ছবি (2) জন্মসনদ (3) আবেদন ফরম — দাখিলা নম্বর দিয়ে গুছিয়ে তোলার অফলাইন Flutter অ্যাপ।

**বর্তমান ভার্সন:** v1.7.0+7 | Flutter 3.47 | Android | Offline First
**ডেটা:** 1,431 জন | `assets/Data_basic.json` | SQLite | Isolate Import
**কোয়ালিটি:** `flutter analyze` 0 issues | `flutter test` 15+ pass

---

## ✅ বর্তমান অবস্থা (Phase 5B পর্যন্ত যা হয়েছে)

### Core (Phase 1-2)
- JSON → SQLite auto-import (Isolate.run, UI freeze নেই)
- 300ms debounce search + stale-result guard
- Camera init error handling + mounted guard
- `image_processor.dart` pure function + unit test
- `forik_no` index, `flutter analyze` 0

### UX (Phase 3)
- Review Screen: Capture → Preview → [আবার তুলুন] [মুছুন] [পরের >]
- Pro Controls: front/back, torch, 3x3 passport grid, pinch-zoom + double-tap reset
- Thumbnail + full-screen viewer + retake/delete
- Forik chips: `ফরিক ৩: 40/120` + tap filter

### Customization (Phase 3C)
- ⚙️ Settings: Custom JSON import (file_picker) + captured preserve + Data Reset
- Class > Forik dynamic dropdown + All
- Folder Open (android_intent_plus) + Path Copy
- Storage: `Pictures/DakhilaCamera/` (MediaStore) — Gallery তে দেখা যায়

### Export & Polish (Phase 5A + 5B)
- **Forik-wise ZIP Export**: `archive` দিয়ে `Class_Mishkat/Forik_1/281.jpg` + `missing.csv`
- **PDF Print Sheet**: `pdf` package — A4 তে 12 ছবি + দাখিলা/নাম ক্যাপশন
- **Gallery Save**: MediaStore → `Pictures/DakhilaCamera`
- **Excel Import**: `excel` package — DAKHILA, STU_NAME হেডার ম্যাপ
- **Quick Wins**: Dark Mode, Settings persist (shared_preferences), Undo delete (5s snackbar), Shutter sound/haptic, Search highlight

### Tech Stack
```
camera 0.10.6, sqflite, provider, image 4.x, path_provider,
file_picker 12, android_intent_plus, archive 3.x, pdf, printing,
share_plus, excel 4.x, shared_preferences, permission_handler
```

---

## 🎯 নতুন টার্গেট: 3-Document System (Photo + Birth Certificate + Form)

একজন ছাত্র = 3 ফাইল। এখন শুধু Photo হয়। বাকি 2টা যোগ করতে হবে।

### ১. নামকরণ ও স্টোরেজ (Final Decision)

**Folder per Student (Recommended):**
```
Pictures/DakhilaCamera/
├── Mishkat/
│   ├── Forik_1/
│   │   ├── 281_Rasel_Mahmud/
│   │   │   ├── 281_PHOTO.jpg (600x800)
│   │   │   ├── 281_BIRTH.jpg (or .pdf)
│   │   │   └── 281_FORM.jpg
│   │   └── 282_Masudur/
│   └── Forik_2/
└── Hifz/
```
**Fallback Flat:** `281_PHOTO.jpg`, `281_BIRTH.pdf` — migration সহজ।

### ২. Database Schema v4 (Migration Plan)

**Old v3:**
```sql
dakhila | stu_name | image_path | is_captured
```

**New v4 - 2 Table Design (Scalable):**
```sql
-- students (master)
CREATE TABLE students (
  dakhila TEXT PRIMARY KEY,
  stu_name TEXT, class_name TEXT, forik_no TEXT,
  father_name TEXT, marhala TEXT, exam_year TEXT,
  total_docs INTEGER DEFAULT 0 -- 0..3
);

-- documents (detail)
CREATE TABLE documents (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  dakhila TEXT,
  doc_type TEXT CHECK(doc_type IN ('PHOTO','BIRTH','FORM')),
  file_path TEXT,
  file_ext TEXT, -- jpg, pdf
  status INTEGER DEFAULT 0,
  updated_at TEXT,
  FOREIGN KEY(dakhila) REFERENCES students(dakhila),
  UNIQUE(dakhila, doc_type)
);
CREATE INDEX idx_doc_dakhila_type ON documents(dakhila, doc_type);
```

**Migration:** v3→v4 `onUpgrade`: পুরনো `image_path` → documents এ `PHOTO` হিসেবে insert, `total_docs` recalc।

### ৩. UI/UX Flow

**ListScreen:** 
```
[🟢📷 🟢📜 🔴📝] 281 - রাসেল মাহমূদ (2/3)
```
3 dot = Photo/Birth/Form status, tap = Document Dashboard.

**DocumentDashboardScreen (NEW):**
- Header: Progress ring 2/3
- 3 Cards:
  - PHOTO Card: thumbnail + [Camera] [Retake] [Delete] + passport toggle
  - BIRTH Card: thumbnail/pdf icon + [Scan] [File Picker PDF/JPG] [View]
  - FORM Card: same
- Each card: status badge, file size, last updated

### ৪. Capture Methods

| Doc | Method 1 | Method 2 | Output |
|-----|----------|----------|--------|
| PHOTO | Camera + 600x800 crop (existing) | Gallery pick | JPG 90% |
| BIRTH | **Document Scanner** (`google_mlkit_document_scanner` or `cunning_document_scanner`) - auto edge detect, perspective correction | File Picker PDF/JPG | JPG/PDF |
| FORM | Same as BIRTH | Same | JPG/PDF |

### ৫. Export v2

- **ZIP Forik-wise:** `Forik_1.zip` → `281/` ফোল্ডারে 3 ফাইল
- **Missing Report v2:** CSV কলাম: `Dakhila, Name, Forik, Photo, Birth, Form, MissingCount`
- **Merged PDF per Student:** 3 doc → 1 PDF (photo + birth + form) for submission

---

## 🚀 রোডম্যাপ (Phase 5B → v2.0)

### Phase 6 - 3Doc Core (1.5 দিন) — v1.8.0
- [ ] DB v4 migration + documents table + `Document` model
- [ ] `DocumentProvider` + `total_docs` logic
- [ ] Storage service: `getStudentFolder(dakhila)` + `getFileName(dakhila, type, ext)`
- [ ] ListScreen 3-dot UI + progress  x/3

### Phase 7 - Dashboard & Scanner (2 দিন) — v1.9.0
- [ ] `document_dashboard_screen.dart` + 3 cards
- [ ] `document_scanner_service.dart` - ML Kit scanner
- [ ] File Picker PDF support (birth/form)
- [ ] PDF viewer (`syncfusion_flutter_pdfviewer` or `printing`)

### Phase 8 - Export & Bulk (1 দিন) — v2.0.0
- [ ] ZIP v2 (folder per student) + Missing CSV v2 + Merged PDF
- [ ] Bulk import: ফাইল নাম `281_BIRTH.pdf` → auto detect + assign
- [ ] Gallery Grid filter: Only missing Birth/Form

### Phase 9 - Release (0.5 দিন) — v2.0.0+10
- [ ] applicationId `com.madrasa.dakhilacamera` + icon + keystore
- [ ] `flutter build apk --release` (~25MB) + `appbundle`
- [ ] Play Store Internal Testing

**Validation per Phase:** `flutter analyze` 0 + `flutter test` + real device 10 students x 3 docs

---

## 🛠️ সেটআপ ও বিল্ড

```bash
flutter pub get
flutter run
flutter test
flutter analyze
flutter build apk --release
flutter build appbundle
```

**Permission (AndroidManifest.xml):**
```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />
```

**APK Location:** `build/app/outputs/flutter-apk/app-release.apk` + `Pictures/DakhilaCamera/` তে সব ফাইল

---

## ⚠️ নোট

- সব ডেটা লোকাল — কোথাও আপলোড হয় না
- BIRTH/FORM PDF হলে thumbnail এর বদলে PDF icon
- Uninstall করলে `Pictures/` এ থাকা ফাইল মুছবে না (MediaStore)
- বাংলা নাম Unicode হতে হবে

বিস্তারিত: `PLAN_3DOC.md`
