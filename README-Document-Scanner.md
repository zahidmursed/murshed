# Dakhila Camera - Document Scanner System
### মূল সিস্টেম - কিভাবে কাজ করবে?

> মোবাইল দিয়ে ডকুমেন্টের ছবি তুললে বাঁকা-ত্যাড়া ডকুমেন্ট অটো সোজা, ফ্রেশ ও পরিষ্কার করার সম্পূর্ণ সিস্টেম।

---

## ১. সিস্টেমের উদ্দেশ্য

মাদ্রাসার ছাত্রদের জন্ম নিবন্ধন, NID, বেফাক এডমিট কার্ড ইত্যাদি কাগজ ম্যানুয়ালি স্ক্যান করা অনেক সময়ের কাজ। এই সিস্টেমে:
- মোবাইল দিয়ে ছবি তুললেই অটো ডিটেক্ট হবে
- বাঁকা ছবি অটো সোজা (Perspective Correction) হবে
- কালো দাগ, ছায়া দূর হয়ে ফটোকপির মতো ফ্রেশ হবে
- ফাইল সেভ হবে `DAKHILA` অনুযায়ী, যেমন: `281_BIRTH.jpg`

---

## ২. কিভাবে কাজ করে? (৪ টি ধাপ)

### ধাপ ১: Auto Edge Detection (কাগজ খোঁজা)
ক্যামেরা চালু করলেই AI কাগজের ৪টি কোনা (Corner) খুঁজে বের করে।
- **Technology:** `Google ML Kit Document Scanner` / `OpenCV`
- **Output:** ৪টি Point - TopLeft, TopRight, BottomRight, BottomLeft
- **UI:** লাইভ ক্যামেরায় সবুজ বর্ডার দেখাবে

### ধাপ ২: Perspective Transform (বাঁকা থেকে সোজা)
এটাই মূল ম্যাজিক। ৪৫ ডিগ্রি কোণ থেকে তুললেও গণিত করে উপর থেকে তোলার মতো সোজা বানায়।

```
Formula:
srcPoints = [বাঁকা ছবির ৪ কোনা]
dstPoints = [0,0], [800,0], [800,1100], [0,1100] // A4 Ratio

Matrix = getPerspectiveTransform(src, dst)
Result = warpPerspective(Image, Matrix)
```

### ধাপ ৩: Image Enhancement (পরিষ্কার করা)
সোজা করার পর ৩টি ফিল্টার:

1.  **Magic Color (Auto):** 
    - Background সাদা, লেখা কালো
    - Brightness +30%, Contrast +20%
    - ছায়া (Shadow) রিমুভ

2.  **Grayscale:**
    - সাদা-কালো, ফাইল সাইজ ৭০% কম

3.  **Black & White (Threshold):**
    - একদম ফটোকপির মতো, শুধু লেখা থাকবে
    - OCR এর জন্য বেস্ট

### ধাপ ৪: Smart Save System
- Path: `/DakhilaCamera/Documents/`
- Naming: `{DAKHILA}_{DOC_TYPE}.jpg`
- Example:
  - `281.jpg` -> পাসপোর্ট ছবি
  - `281_BIRTH.jpg` -> জন্ম নিবন্ধন
  - `281_NID.jpg` -> NID
  - `281_BEFAC_117971.jpg` -> এডমিট

---

## ৩. Flutter Implementation Plan

### pubspec.yaml
```yaml
dependencies:
  google_mlkit_document_scanner: ^0.2.0 # গুগলের অফিসিয়াল স্ক্যানার
  edge_detection: ^1.0.5               # ম্যানুয়াল কর্নার টানা
  opencv_dart: ^1.3.0                   # Perspective ম্যাথ
  image: ^4.1.7                         # ফিল্টার
  path_provider: ^2.1.2
  sqflite: ^2.3.2
```

### Folder Structure
```
lib/
├── models/
│   └── student.dart
├── db/
│   └── database_helper.dart
├── screens/
│   ├── list_screen.dart          # ছাত্র লিস্ট
│   ├── camera_screen.dart        # পাসপোর্ট ছবি
│   └── document_scanner_screen.dart # ডকুমেন্ট স্ক্যানার
├── services/
│   ├── scanner_service.dart      # ML Kit Logic
│   └── image_processor.dart      # Filter Logic
└── main.dart
```

### Core Code Snippet
```dart
// document_scanner_screen.dart
final scanner = DocumentScanner(
  options: DocumentScannerOptions(
    documentFormat: DocumentFormat.jpeg,
    mode: ScannerMode.full,
    isGalleryImport: false,
    pageLimit: 5
  )
);

final result = await scanner.scanDocument();
if(result != null){
  // result.images[0] -> Already straightened & cleaned by Google ML Kit
  String savePath = "${dir.path}/${student.dakhila}_BIRTH.jpg";
  await File(result.images[0]).copy(savePath);
}
```

---

## ৪. অ্যাপের Workflow (User Flow)

1.  App Open -> JSON Load (তোমার Data_basic.json)
2.  ছাত্র সিলেক্ট -> 281 - রাসেল মাহমূদ
3.  দুটি বাটন: [ 📸 ছবি তোলা ] [ 📄 ডকুমেন্ট স্ক্যান ]
4.  ডকুমেন্ট টাইপ সিলেক্ট: জন্ম নিবন্ধন / NID / বেফাক রোল
5.  ক্যামেরা -> অটো ডিটেক্ট -> অটো ক্যাপচার
6.  Preview -> ৪টি কর্নার টেনে ঠিক করার সুযোগ -> ফিল্টার চুজ
7.  Save -> SQLite এ `is_doc_scanned = 1` আপডেট

---

## ৫. কেন Google ML Kit বেস্ট?

| Feature | ML Kit | Custom OpenCV |
| :--- | :--- | :--- |
| বাঁকা-ত্যাড়া সোজা | 100% Auto | Manual করতে হয় |
| ছায়া দূর | Auto | কোড লিখতে হয় |
| স্পিড | খুব দ্রুত | মাঝারি |
| কোড | ১০ লাইন | ২০০+ লাইন |

**সাজেশন:** ML Kit দিয়ে শুরু করো। পরে চাইলে OpenCV দিয়ে Manual Mode যোগ করা যাবে।

---

## ৬. পরবর্তী ফিচার

- [ ] Batch Scan: একসাথে ৫০টা কাগজ স্ক্যান
- [ ] PDF Export: এক ছাত্রের সব ডকুমেন্ট এক PDF এ
- [ ] OCR: জন্ম নিবন্ধন নম্বর অটো পড়ে নেবে
- [ ] ZIP Export: সব ছবি + ডকুমেন্ট এক ZIP এ

---

## ৭. Installation

```bash
flutter pub get
flutter run

# Release APK
flutter build apk --release
```

**Developer:** Zahid Murshed
**Data Source:** Data_basic.json (DAKHILA_YEAR: 2025)
**Version:** 2.0.0 - Document Scanner Edition
