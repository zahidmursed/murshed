# Release APK তৈরি

প্রজেক্টের মূল ফোল্ডারে থাকা `build_release_apk.bat` ফাইলটিতে ডাবল-ক্লিক করুন। অথবা PowerShell/CMD থেকে চালান:

```bat
build_release_apk.bat
```

প্রথমবার release APK বিতরণের আগে `create_release_keystore.bat` একবার চালান। এটি আপনার password দিয়ে signing key তৈরি করবে। `android\app\upload-keystore.jks` এবং `android\key.properties` নিরাপদে backup রাখুন; এগুলো হারালে পরের APK পুরোনোটির update হিসেবে ইনস্টল হবে না।

স্ক্রিপ্টটি pubspec.yaml-এর build number (যেমন version: 2.1.1+22-এর +22) স্বয়ংক্রিয়ভাবে ১ বাড়িয়ে সেটি APK-তে ব্যবহার করে — কোনো সংখ্যা টাইপ করতে হয় না। তারপর dependency নেয়, পুরনো build পরিষ্কার করে, এবং বর্তমান কোড দিয়ে signed release APK তৈরি করে। নতুন APK পাওয়া যাবে build\app\outputs\flutter-apk ফোল্ডারে।

বেশিরভাগ নতুন Android ফোনে `app-arm64-v8a-release.apk` ইনস্টল করুন।

## সময়সীমাবদ্ধ Trial APK

`build_trial_apk.bat` চালান। এটি ৩০ বা ৬০ দিনের মেয়াদ বেছে নিতে বলবে এবং মেয়াদসহ APK তৈরি করবে। APK প্রথমবার চালুর দিন থেকে মেয়াদ গণনা করে; মেয়াদ শেষ হলে অ্যাপের কাজের স্ক্রিনের বদলে expiry message দেখাবে।

Trial APK-ও signed release APK; তাই প্রথমে একবার create_release_keystore.bat চালানো আবশ্যক। Build number-ও release-এর মতোই pubspec.yaml থেকে স্বয়ংক্রিয়ভাবে ১ বাড়িয়ে নেওয়া হয়।

নতুন Android ফোনে `build\app\outputs\flutter-apk\trial-30-days` অথবা `trial-60-days` ফোল্ডারের `arm64-v8a` APK পাঠান।

### ইউনিভার্সাল Trial APK (এক ফাইল, সব ফোন)

ফোনের আর্কিটেকচার না জানা থাকলে `build_trial_universal_apk.bat`-এ ডাবল-ক্লিক করুন — ৩০/৬০ দিনের মেয়াদ বেছে নিতে বলবে, তারপর split ছাড়া বিল্ড করে একটাই ফাইল বানাবে (যেমন dakhila-camera-trial-30-days-v2.1.1+25-universal.apk)। Keystore, build number অটো-ইনক্রিমেন্ট, মেয়াদ-গণনা (TRIAL_DAYS) — সব build_trial_apk.bat-এর মতোই, শুধু ABI-ভাগ নেই।

## ইউনিভার্সাল APK (এক ফাইল, সব ফোন)

ফোনের আর্কিটেকচার (32-bit/64-bit) না জানা থাকলে বা একটাই ফাইল সবাইকে পাঠাতে চাইলে `build_universal_apk.bat`-এ ডাবল-ক্লিক করুন:

```bat
build_universal_apk.bat
```

এটি `--split-per-abi` ছাড়া বিল্ড করে, ফলে `build\\app\\outputs\\flutter-apk` ফোল্ডারে `dakhila-camera-v<version>-universal.apk` নামে একটাই APK তৈরি হয় (যেমন `dakhila-camera-v2.1.1+24-universal.apk`) — সব Android ফোনে ইনস্টল হবে। Keystore, build number অটো-ইনক্রিমেন্ট, clean/pub get ধাপগুলো `build_release_apk.bat`-এর মতোই।

| পদ্ধতি | ফাইল | কখন ব্যবহার করবেন |
|---|---|---|
| `build_release_apk.bat` (split) | প্রতি ABI আলাদা, ছোট ফাইল | ফোন 64-bit নিশ্চিত (বেশিরভাগ নতুন ফোন) — `app-arm64-v8a-release.apk` |
| `build_universal_apk.bat` | এক ফাইল, তুলনামূলক বড় | কোন ফোনে যাবে জানা নেই / একটাই ফাইল শেয়ার করতে চাইলে |
