# Dakhila Camera — স্থিতিশীলতা ও ভবিষ্যৎ পরিকল্পনা

এই পরিকল্পনার উদ্দেশ্য হলো নতুন ফিচার যোগের আগে ডেটা নিরাপত্তা, APK আপডেট এবং মাঠে ব্যবহারের নির্ভরযোগ্যতা নিশ্চিত করা।

## Phase 1 — Release blocker ও data safety

1. স্টোরেজ সাজানোর সময় পুরোনো source file মুছার আগে source path আলাদা ভ্যারিয়েবলে ধরে রাখুন। copy সফল ও database update নিশ্চিত হওয়ার পরেই সেই original file মুছতে হবে।
2. `v2`-এর পুরোনো flat layout (`<দাখিলা>/<দাখিলা>_PHOTO.jpg`) থেকে নতুন `PHOTO/BIRTH/FORM/<দাখিলা>.jpg` layout-এ database-সহ idempotent migration যোগ করুন। মাঝপথে ব্যর্থ হলে পুরোনো কপি অক্ষত থাকবে।
3. APK build script-এ versionCode/build number বাধ্যতামূলক করুন। একই app update হিসেবে ইনস্টলের জন্য প্রতিটি বিতরণে আগের চেয়ে বড় versionCode দরকার।
4. স্থায়ী release keystore তৈরি ও backup করুন। keystore ছাড়া নতুন APK পুরোনো APK-এর ওপর update হিসেবে ইনস্টল নাও হতে পারে।
5. একবারে একটি non-photo document save করুন; camera flow-এ duplicate database upsert বাদ দিন।

**সফলতার মানদণ্ড:** পুরোনো ছবি/তিন ডকুমেন্ট migration-এর পরে view, delete, ZIP export ও restore কাজ করবে; fresh এবং upgrade—দুই ইনস্টলেই পরীক্ষা হবে।

## Phase 2 — Camera quality ও workflow

1. 431×531 crop guide-কে camera preview-এর visible area অনুযায়ী ঠিক করুন।
2. Review screen-এ non-destructive manual crop যোগ করুন: drag, pinch zoom, reset এবং apply। original capture অস্থায়ীভাবে রাখুন, apply-এর পর 431×531 JPEG তৈরি করুন।
3. Auto-enhancement-এ on/off ও তিনটি preset দিন: Natural, Fresh, Bright। একই ছবি বারবার process করলে ফল একই থাকবে।
4. কম আলো/blur শনাক্ত করে capture-এর আগে সতর্কতা দিন; autofocus/auto-exposure settle হওয়ার পর shutter enable করা যায় কি না পরীক্ষা করুন।
5. প্রকৃত Android ফোনে front/back camera, torch, portrait/landscape, low-memory এবং বড় image capture পরীক্ষা করুন।

## Phase 3 — Trial ও বিতরণ

1. Trial APK এবং full APK-এর version name ও build number স্পষ্টভাবে আলাদা করুন।
2. Offline trial-এর সীমাবদ্ধতা UI ও বিতরণ নথিতে লিখুন: app data clear বা সময় বদলালে bypass সম্ভব।
3. শক্ত trial/license দরকার হলে server-side activation, device-bound token এবং সীমিত offline grace period ডিজাইন করুন।
4. Trial expiry screen-এ প্রতিষ্ঠান/যোগাযোগের তথ্য ও full version পাওয়ার নির্দেশনা যোগ করুন।

## Phase 4 — Quality assurance ও automation

1. Unit test: 431×531 crop, auto-enhancement range, storage path, 3-doc overwrite, database v5 migration, trial expiry।
2. Integration test: import → photo/birth/form capture → review → retake → delete/undo → ZIP export।
3. Release checklist: `flutter analyze`, `flutter test`, device smoke test, APK install/update test, size check।
4. CI pipeline: analyze/test এবং signed APK artifact build।

## Phase 5 — Office features

1. ক্লাস/ফরিক অনুযায়ী backup ও one-tap restore।
2. CSV/ZIP report-এ guardian mobile field (privacy control-সহ)।
3. Photo quality/size preset এবং storage usage dashboard।
4. Multi-year data archive ও read-only completed session।

## Security ও privacy নীতি

- ছাত্রের নাম, অভিভাবকের নম্বর ও ছবি সংবেদনশীল তথ্য; export/share করার আগে scope confirmation দরকার।
- database/backup encryption এবং optional app lock ভবিষ্যতে বিবেচ্য।
- release signing key ও backup password source control-এ রাখা যাবে না।
