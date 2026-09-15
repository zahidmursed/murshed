# Release APK তৈরি

প্রজেক্টের মূল ফোল্ডারে থাকা `build_release_apk.bat` ফাইলটিতে ডাবল-ক্লিক করুন। অথবা PowerShell/CMD থেকে চালান:

```bat
build_release_apk.bat
```

প্রথমবার release APK বিতরণের আগে `create_release_keystore.bat` একবার চালান। এটি আপনার password দিয়ে signing key তৈরি করবে। `android\app\upload-keystore.jks` এবং `android\key.properties` নিরাপদে backup রাখুন; এগুলো হারালে পরের APK পুরোনোটির update হিসেবে ইনস্টল হবে না।

স্ক্রিপ্টটি Android build number চাইবে। একই অ্যাপের update হিসেবে ইনস্টলের জন্য প্রতিবার আগের চেয়ে বড় সংখ্যা দিন। তারপর dependency নেয়, পুরনো build পরিষ্কার করে, এবং বর্তমান কোড দিয়ে signed release APK তৈরি করে। নতুন APK পাওয়া যাবে `build\app\outputs\flutter-apk` ফোল্ডারে।

বেশিরভাগ নতুন Android ফোনে `app-arm64-v8a-release.apk` ইনস্টল করুন।

## সময়সীমাবদ্ধ Trial APK

`build_trial_apk.bat` চালান। এটি ৩০ বা ৬০ দিনের মেয়াদ বেছে নিতে বলবে এবং মেয়াদসহ APK তৈরি করবে। APK প্রথমবার চালুর দিন থেকে মেয়াদ গণনা করে; মেয়াদ শেষ হলে অ্যাপের কাজের স্ক্রিনের বদলে expiry message দেখাবে।

Trial APK-ও signed release APK; তাই প্রথমে একবার `create_release_keystore.bat` চালানো আবশ্যক এবং প্রতিবার আগের APK-এর চেয়ে বড় build number দিতে হবে।

নতুন Android ফোনে `build\app\outputs\flutter-apk\trial-30-days` অথবা `trial-60-days` ফোল্ডারের `arm64-v8a` APK পাঠান।
