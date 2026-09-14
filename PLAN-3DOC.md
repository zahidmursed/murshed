# Dakhila Camera — 3-Document System পরিকল্পনা (Phase 5B → v2.0)

> সংশোধিত স্ট্যাটাস: **v1.7.0+9** | Phase 4/5A/5B/**6** ✅ সম্পন্ন | Target: v2.0 (Photo + Birth + Form)
> ✅ **এটিই active প্ল্যান** (README-V2-এর সাথে সঙ্গতিপূর্ণ)

---

## ১. বর্তমান অবস্থা (Phase 5B পর্যন্ত)

**যা আছে:**
- `lib/models/student.dart` + `forik_stat.dart`
- `lib/db/database_helper.dart` v3: index on forik_no, getDistinctClasses(), getForiksForClass(), getForikStats(), replaceAllStudents() with captured preserve
- `lib/providers/student_provider.dart`: debounce 300ms, class>forik filter, search persist, settings persist via shared_preferences
- `lib/utils/image_processor.dart`: pure `processPassportBytes()` isolate-safe + 4 unit tests
- `lib/screens/`: list_screen (thumbnail, progress chips, 3-filter), camera_screen (torch, front/back, grid, pinch-zoom), review_screen (retake/delete/next), image_viewer_screen, settings_screen (JSON import, folder open)
- `lib/services/`: export_service (Forik-wise ZIP + missing.csv), media_store_service (Pictures/DakhilaCamera), file_service (undo delete)
- **Features:** JSON+Excel import, Gallery save, PDF print sheet (12/A4), ZIP export, Dark Mode, Undo, Shutter feedback

**সমস্যা যা এখনো আছে (3-Doc এর জন্য Blocker):**
1. 1 student = 1 file (image_path) — 3 file এর জায়গা নেই
2. Storage flat — `281.jpg` — Birth/Form PDF হলে clash
3. Progress 0/1 — 0/3 দরকার
4. Export ZIP শুধু Photo — Birth/Form নেই

---

## ২. 3-Doc এর জন্য ডিজাইন ডিসিশন

### A. Database: Single Table vs Two Table?

**Decision: Two Table (students + documents)** — Scalable, ভবিষ্যতে NID, সনদ যোগ করা যাবে।

**Schema v4:**
```sql
-- migration from v3
ALTER TABLE students ADD COLUMN total_docs INTEGER DEFAULT 0;

CREATE TABLE documents (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  dakhila TEXT NOT NULL,
  doc_type TEXT NOT NULL CHECK(doc_type IN ('PHOTO','BIRTH','FORM')),
  file_path TEXT NOT NULL,
  file_ext TEXT NOT NULL, -- jpg, jpeg, pdf, png
  mime_type TEXT, -- image/jpeg, application/pdf
  file_size INTEGER,
  status INTEGER DEFAULT 1,
  updated_at TEXT,
  FOREIGN KEY(dakhila) REFERENCES students(dakhila) ON DELETE CASCADE,
  UNIQUE(dakhila, doc_type)
);
```

**Model:**
```dart
enum DocType { PHOTO, BIRTH, FORM }

class StudentDocument {
  final String dakhila;
  final DocType type;
  final String path;
  final String ext;
  final int status;
}

class StudentWithDocs {
  final Student student;
  final Map<DocType, StudentDocument?> docs; // 3 slots
  int get completedCount => docs.values.where((d)=> d!=null).length;
  double get progress => completedCount / 3;
}
```

### B. Storage Path Strategy

**Final Path:**
```
Pictures/DakhilaCamera/
  v2/
    Mishkat/
      Forik_1/
        281/
          281_PHOTO.jpg
          281_BIRTH.pdf
          281_FORM.jpg
          .meta.json (optional: timestamps)
```

**Service:**
```dart
class StorageService {
  Future<Directory> getStudentFolder(String className, String forik, String dakhila);
  String fileName(String dakhila, DocType type, String ext) => "${dakhila}_${type.name}.$ext";
  Future<void> migrateFromV3(); // old flat → new folder
}
```

### C. UI Flow (Detail)

**ListScreen Tile:**
```
[Avatar] 281 - রাসেল মাহমূদ
        Mishkat | Forik 1
        [●●○] 2/3  (green green grey)
        Trailing: [📁] open folder
```

**On Tap → DocumentDashboardScreen:**
- AppBar: 281 - Progress 2/3 with CircularProgress
- 3 Cards vertical:
  - Card PHOTO: if exists show thumbnail 600x800, else placeholder + buttons: [📷 Camera] [🖼 Gallery]
  - Card BIRTH: if pdf show PDF icon + size, if jpg thumbnail + [📷 Scan] [📄 PDF Pick]
  - Card FORM: same
- Each card has overflow: View, Retake, Delete, Share
- Bottom: [Export This Student as ZIP] [Merge 3 as PDF]

### D. Scanner Implementation

**Option 1 (Recommended): `cunning_document_scanner`**
- No Google Play Services dependency, works offline
- Returns cropped image path
- For PDF: after scan, convert images to PDF via `pdf` package if multiple pages

**Option 2: `google_mlkit_document_scanner`**
- Better accuracy, but needs Play Services + internet first time
- GMS scanner UI

**Implementation:**
```dart
class DocScannerService {
  Future<String?> scanAsImage(); // returns jpg path
  Future<String?> pickFile({List<String> allowedExt = ['jpg','pdf']});
  Future<String> imagesToPdf(List<String> imagePaths, String outputPath);
}
```

---

## ৩. Phase-wise Implementation (5B → v2.0)

### Phase 6 - Core Data & Storage — ✅ সম্পন্ন (2026-09-14) — v1.7.0+9

| Task | File | অবস্থা |
|------|------|-----|
| DB v4 migration + documents table + index ✅ | database_helper.dart (onUpgrade 2→4, copy-not-move, idempotent INSERT OR IGNORE) |
| Models: DocType/StudentDocument/StudentWithDocs ✅ (+ Student-এ marhala/exam_year/total_docs) | models/document.dart, models/student.dart |
| StorageService: folder per student, fileName, copyToStudentFolder ✅ (migrateFromV3-এর বদলে provider.migrateStorageToV2) | services/storage_service.dart |
| Provider doc-aware ✅ (আলাদা DocumentProvider নয় — student_provider-এই: doc map, markCaptured/clear/restore/recover doc আপডেট, migrateStorageToV2) | providers/student_provider.dart |
| ListScreen ৩-ডট ●●○ + x/3 ✅ | list_screen.dart |
| ⚙️ Settings: "স্টোরেজ সাজান (v2 ফোল্ডার)" মাইগ্রেশন বাটন ✅ | settings_screen.dart |

**Test:** `flutter test` → **21/21 পাস** (`document_db_test.dart`: v2→v4 migration পুরনো ছবি প্রিজার্ভ + fresh v4 schema)

### Phase 7 - Dashboard + Capture — ✅ সম্পন্ন (2026-09-14) — v1.8.0+10 • 🔧 v1.8.1: BIRTH = JPEG-only

| Task | অবস্থা |
|------|-----|
| document_dashboard_screen + 3 cards + progress ring ✅ (Consumer-live, per-type status chip) |
| Photo capture reuse via dashboard ✅ (camera push; নতুন ছবি v2 ফোল্ডারে সেভ) |
| File Picker PDF/JPG for BIRTH/FORM ✅ (ML Kit scanner — Phase 8-এ স্থগিত) |
| PDF/document view ✅ (native `viewFile` channel — system viewer, শূন্য dependency) |
| Bulk filename parser ✅ (`281_BIRTH.pdf` → auto assign; Settings-এ multiple pick; টেস্ট সহ) |
| Settings: storage info ✅ (আগেই আছে) |

**নোট:** export_service-এর doc_type filter → Phase 8 (Export v2)।
**🔧 v1.8.1:** BIRTH (২য় ডক) **শুধু JPEG/PNG** — File Picker থেকে PDF বাদ,
bulk import-এ `281_BIRTH.pdf` রিজেক্ট, `assignDocument`-এ গার্ড;
`DocType.allowedExtensions` দিয়ে প্রতি-টাইপ নিয়ম কেন্দ্রীভূত।
**Validation:** analyze 0, tests 23/23, APK v1.8.1 বিল্ড সফল।

### Phase 8 - Export v2 & Bulk Ops — ✅ সম্পন্ন (2026-09-14) — v1.9.0+14

| Task | অবস্থা |
|------|-----|
| ZIP v2: ছাত্র-প্রতি ফোল্ডারে ৩ ডক + `_reports/missing.csv` + `summary.txt` ✅ (streaming encoder, doc-aware) |
| Missing CSV v2 ✅ (কলাম: Dakhila, Name, Photo/Birth/Form yes/no + MissingCount) |
| Merged PDF per student ✅ (`exportStudentMergedPdf` — প্রতি ডক এক A4 পেজ; Dashboard বাটন → শেয়ার শিট) |
| Gallery Grid: missing-type filter chips ✅ (জন্মসনদ বাকি/ফরম বাকি) |

**Export Example:**
```
Dakhila_Forik1_2025-09-14.zip
├── 281_Rasel/
│   ├── 281_PHOTO.jpg
│   ├── 281_BIRTH.pdf
│   └── 281_FORM.jpg
├── 282/
└── _reports/
    ├── missing.csv
    └── summary.txt (Forik 1: 120 students, 300/360 docs done)
```

### Phase 9 - Polish & Release (Day 5, 4h) — v2.0.0+10

- [ ] applicationId `com.madrasa.dakhilacamera` + icon
- [ ] Keystore + signingConfig + shrinkResources
- [ ] `flutter build apk --release` + `appbundle`
- [ ] Integration test: import Excel → capture 3 docs → ZIP → verify
- [ ] README + PLAN update + screenshots

---

## ৪. Risk & Mitigation

| Risk | Mitigation |
|------|------------|
| Old photos lost during migration | migrateFromV3 copies, not moves; keep backup in old path until user confirms |
| PDF too large (birth cert 5MB) | Compress: image to 1200px, PDF via `pdf` re-encode, limit 2MB per file |
| Storage permission Android 13+ | Use MediaStore, no MANAGE_EXTERNAL_STORAGE needed, only READ_MEDIA_IMAGES |
| 1431×3 = 4293 files slow | Pagination 50, thumbnail cache LRU 100, documents query only for visible students |

---

## ৫. Success Criteria for v2.0

- [ ] একজন ছাত্রের 3টা ফাইল তোলা যায় (Camera + File Picker PDF)
- [ ] List এ 3 dot + 2/3 progress সঠিক
- [ ] Folder per student Pictures/ এ আছে, Gallery তে দেখা যায়
- [ ] ZIP Forik-wise + missing.csv + merged PDF কাজ করে
- [ ] Bulk import `281_BIRTH.pdf` নামে ফাইল দিলে auto assign
- [ ] `flutter analyze` 0, `flutter test` 20+ pass, APK < 30MB release signed

---

## ৬. Next Immediate Action (Today) — ✅ সম্পন্ন

1. ✅ `models/document.dart` + DB v4 migration (onUpgrade 2→4, পুরনো ছবি PHOTO doc)
2. ✅ `services/storage_service.dart` with folder per student
3. ✅ `list_screen.dart` 3-dot UI + x/3 progress

**পরবর্তী:** Dashboard screen (Phase 7)।

