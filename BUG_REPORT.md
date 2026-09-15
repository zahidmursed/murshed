# 🐞 Dakhila Camera — গভীর কোড রিভিউ ও বাগ রিপোর্ট

**তারিখ:** 2026-09-15 • **ভার্সন:** 2.1.0+16 • **স্কোপ:** `lib/` (২১ ফাইল) + `android/` (MainActivity.kt, Manifest)
**বেসলাইন স্বাস্থ্য:** `flutter analyze` → ৪টি info • `flutter test` → ২৬/২৬ পাস ✅ • Git clean
**ফিক্স স্ট্যাটাস (2026-09-15):** রিপোর্টের **সব ১৭টি আইটেম** ঠিক করা হয়েছে → `flutter analyze` = 0 issues, `flutter test` = **২৮/২৮ পাস** (২টি নতুন regression টেস্টসহ) ✅

---

## 🔴 হাই সিভারিটি (ব্যবহারকারী-দৃশ্যমান ভুল)

### ১. ক্লাস ফিল্টার করা অবস্থায় প্রগ্রেস chip-গুলো সব ক্লাসের ফরিক দেখায় — ✅ ফিক্স হয়েছে
- **ফাইল:** `lib/providers/student_provider.dart`
- **সমস্যা:** `load()`-এ স্ট্যাট আসে `getForikStats(classFilter: selectedClass)` দিয়ে — ঠিক। কিন্তু
  যেকোনো অ্যাকশনের পরে রিফ্রেশ হয় **ফিল্টার ছাড়া** `getForikStats()`:
  - `markCaptured()` (~লাইন 198) — ছবি তোলার পরে
  - `clearCaptured()` (~লাইন 272) — মোছার পরে
  - `markDocumentSaved()` (~লাইন 231), `assignDocument()` (~লাইন 597), `removeDocument()` (~লাইন 617),
    `restoreFromTrash()` (~লাইন 340), `recoverFromGallery()` (~লাইন 425)
- **প্রভাব:** ক্লাস ফিল্টার চালু থাকলে প্রথম ছবি তোলা/মাত্রই উপরের ফরিক chip-গুলোতে
  অন্য ক্লাসের ফরিকও ঢুকে যায় এবং হিসাব ভুল দেখায়।
- **ফিক্স (প্রস্তাবিত):** provider-এ একটি helper:
  ```dart
  Future<void> _refreshForikStats() {
    final cls = selectedClass.isEmpty ? null : selectedClass;
    return DatabaseHelper.instance.getForikStats(classFilter: cls)
        .then((s) => _forikStats = s);
  }
  ```
  এবং সব `getForikStats()` কল এর দিয়ে বদলানো।

### ২. Undo delete ও গ্যালারি রিকভারি পুরনো (v1 flat) লেআউটে ফাইল ফেরত বসায় — ✅ ফিক্স হয়েছে
- **ফাইল:** `lib/providers/student_provider.dart`
- **সমস্যা:** `restoreFromTrash()`-এ গন্তব্য `'<appDir>/DakhilaCamera/<দাখিলা>.jpg'` এবং
  `recoverFromGallery()`-তেও `'<appDir>/DakhilaCamera/<দাখিলা>.jpg'` — অথচ নতুন ক্যাপচার সেভ হয়
  v2 লেআউটে: `DakhilaCamera/v2/<ক্লাস>/Forik_<n>/<দাখিলা>/PHOTO/<দাখিলা>.jpg`।
- **প্রভাব:** Undo/রিকভারির পর ফাইল পুরনো flat ফোল্ডারে থাকে → ফোল্ডার-গঠন অসঙ্গত;
  পরে আবার তুললে নতুন ফাইল v2-তে যায়, পুরনো ফাইল flat ফোল্ডারে **অপরিচ্ছন্ন থেকে যায়** (orphan)।
  সমাধান হিসেবে "পুরনো ছবি সাজানো" (migrate) টুল চালাতে হয়।
- **ফিক্স (প্রস্তাবিত):** দুই জায়গাতেই গন্তব্য হিসাব করুন:
  ```dart
  final dest = await StorageService.documentPath(
      target.className, target.forikNo, dakhila, DocType.PHOTO, 'jpg');
  ```

---

## 🟠 মিডিয়াম সিভারিটি

### ৩. ট্র্যাশ ফাইল ফাঁকি থেকে যেতে পারে (leak) — ✅ ফিক্স হয়েছে
- **ফাইল:** `student_provider.dart` → `_scheduleTrashCleanup()`
- Undo-র ৬ সেকেন্ড উইন্ডোর মধ্যে অ্যাপ kill/background-এ মারা গেলে `Future.delayed` আর চলে না →
  `Trash/` ফোল্ডারে ফাইল জমে থাকে; পরে কোনো sweep নেই।
- **ফিক্স:** অ্যাপ স্টার্টে (বা settings-এ) `Trash/` ফোল্ডারের সব পুরনো ফাইল মুছে দেওয়া।

### ৪. UI থ্রেডে synchronous ডিস্ক I/O — বড় ডেটায় jank — ✅ ফিক্স হয়েছে
- `lib/screens/gallery_screen.dart` (~লাইন 59): build-এর ভিতরে প্রতিটি doc-এর জন্য
  `File(doc.filePath).existsSync()` — ১৪০০+ ছাত্র × ৩ ডক = হাজার খানেক sync stat কল প্রতি rebuild-এ।
- `lib/screens/list_screen.dart` (~লাইন 186): `FileImage(File(s.imagePath!))` — thumbnail-এ
  **পুরো রেজোলিউশনের** ছবি ডিকোড হয় (নেই `cacheWidth`) → ১৪০০ রো-তে মেমোরি চাপ।
- **ফিক্স:** থাম্বনেইলে `Image.file(..., cacheWidth: 96)` (বা `ResizeImage`), গ্যালারিতে
  existence-check একবার (doc লোডের সময়) বা async-ভাবে।

### ৫. Document Dashboard থেকে PHOTO মোছায় Undo নেই — ✅ ফিক্স হয়েছে
- `document_dashboard_screen.dart` → `removeDocument(PHOTO)` ফাইল **সরাসরি** ডিলিট করে,
  যেখানে viewer/review-এর delete-এ ট্র্যাশ + ৫ সেকেন্ড পুনরুদ্ধার আছে। UX অসঙ্গত।

### ৬. PDF প্রিন্ট শিট পুরোটা মেমোরিতে তৈরি হয় — ✅ ফিক্স হয়েছে (isolate-এ ডাউনস্কেল)
- `lib/services/export_service.dart` → `exportPdfSheet()` — `pw.Document`-এ সব পেজ মেমোরিতে;
  ১০০০+ ছবির স্কোপে low-end ফোনে OOM সম্ভাবনা। (ZIP streaming — ভালো; PDF নয়।)

---

## 🟡 লো সিভারিটি / কসমেটিক

> ✅ **ফিক্স সম্পন্ন (2026-09-15):** নিচের #৭–১৫ **সব আইটেম** ঠিক করা হয়েছে —
> mime হেল্পার `StudentDocument.mimeTypeForExt()`/`mimeTypeForView` (Dart + Kotlin
> দুই জায়গায়), LIKE wildcard escape (+ regression টেস্ট), CSV sanitize (`_csvSafe`),
> temp-capture cleanup (১ ঘণ্টা), ক্রপে `updated_at` রিফ্রেশ, `markDocumentSaved`-এ
> mimeType, `load()` reentrancy guard (চেইন-করা কিউ), dynamic বর্তমান-বছর ডিফল্ট।
> মূল সমস্যার বর্ণনা রেফারেন্স হিসেবে রাখা হলো।

| # | ফাইল | সমস্যা |
|---|---|---|
| ৭ | `document_dashboard_screen.dart` `_viewDoc`, `gallery_screen.dart` `_open` | PNG ফাইলের mime `image/jpeg` পাঠানো হয় — `image/png` হওয়া উচিত |
| ৮ | `MainActivity.kt` `saveToGallery` | সব ইমেজে MIME `image/jpeg` হার্ডকোড — PNG BIRTH/FORM ব্যাকআপ ভুল mime-এ MediaStore-এ যায় |
| ৯ | `database_helper.dart` `search()` | LIKE-এ `%`/`_` wildcard escape নেই (সার্চে `%` লিখলে অপ্রত্যাশিত ম্যাচ) |
| ১০ | `export_service.dart` `_statusCsvContent` | CSV formula injection (`=`, `+`, `-`, `@` দিয়ে শুরু হওয়া নাম) sanitize নেই — অফলাইন অ্যাপে ঝুঁকি কম |
| ১১ | `storage_service.dart` `temporaryCapturePath` | ক্যাপচারের পর অ্যাপ kill হলে raw temp ফাইল জমতে থাকে — periodic cleanup নেই |
| ১২ | `review_screen.dart` `_crop` | ক্রপের পরে documents-এর `updated_at` আপডেট হয় না (ড্যাশবোর্ডে পুরনো তারিখ দেখায়) |
| ১৩ | `student_provider.dart` `markDocumentSaved` | ক্যামেরা থেকে BIRTH/FORM সেভে `mimeType` সেট হয় না (null) |
| ১৪ | `student_provider.dart` `load()` | reentrancy guard নেই — দ্রুত ফিল্টার ট্যাপে দুটো load ইন্টারলিভ করতে পারে |
| ১৫ | `student.dart` | `dakhilaYear`-এর ডিফল্ট `'2025'` হার্ডকোড |
| ১৬ | `trial_service.dart:23` | ~~`Duration(days: trialDays)` — `const` হতে পারে (analyzer)~~ ✅ ফিক্স |
| ১৭ | `review_screen.dart:47,111,145` | ~~`if`-এ curly braces নেই (analyzer ×৩)~~ ✅ ফিক্স |

---

## ✅ যা ভালো আছে

- **২৬/২৬ টেস্ট পাস**; isolate-এ ভারী কাজ (JSON পার্স, image processing, Excel) — UI freeze এড়ানো হয়েছে
- DB মাইগ্রেশন idempotent (`_addColumnIfMissing`) — v2→v6 পর্যন্ত সব কলাম কভার (class_level v6-এ, marhala/exam_year v4-এ) — মাইগ্রেশন গ্যাপ নেই
- `replaceAllStudents` এক ট্রানজেকশনে চলে এবং তোলা ছবির স্ট্যাটাস প্রিজার্ভ করে
- ZIP এক্সপোর্ট streaming encoder — মেমোরি-নিরাপদ
- সার্চে stale-result guard (`_searchRequest`) + 300ms debounce
- প্রায় সব async gap-এ `mounted` চেক — context-after-dispose ঝুঁকি সামলানো
- Trial-এ ঘড়ি পেছনে দেওয়া রোধ (rollback detection)

## 🧪 ভেরিফিকেশন

রিপোর্ট তৈরির সময়: `flutter analyze` (৪ info), `flutter test` (২৬/২৬ ✅)।
কোনো ফিক্স প্রয়োগ করলে প্রতিটির পরে এই দুটি কমান্ড আবার চালান।
