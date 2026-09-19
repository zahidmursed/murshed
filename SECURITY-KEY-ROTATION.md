# 🔐 Release Key ও Secret নিরাপত্তা — রোটেশন রুনবুক

**কেন:** `PLAN-3DOC.md`-এ release keystore-এর পাসওয়ার্ড লেখা অবস্থায় git-এ commit
হয়েছিল (`git log -S 'DakhilaCam@2026'` → commit `ee4b4c1`)। ওই পাসওয়ার্ডই
`android/key.properties` ও `android/key/upload-keystore.jks`-এ ব্যবহৃত হয়েছিল।
ফলে রিপো কপি হাতে যার আছে, সে signing password জানে — সাথে `.jks` ফাঁস হলে
আপনার অ্যাপের নামে APK signed করা সম্ভব।

> **এখনই করুন:** (১) নিচের ধাপে নতুন keystore/পাসওয়ার্ডে যান, (২) ডকে-লেখা
> পাসওয়ার্ড আর কখনো ব্যবহার করবেন না, (৩) history scrub (নিচে) চালান,
> (৪) `.jks` + পাসওয়ার্ড অফলাইন ২ কপি ব্যাকআপ রাখুন।

---

## ১. নতুন keystore-এ রোটেট করা

```bat
:: ইন্টারঅ্যাকটিভ — পাসওয়ার্ড চাওয়া হবে (স্ক্রিনে দেখা যাবে, তাই একান্ত টার্মিনালে চালান)
rotate_release_keystore.bat
```

স্ক্রিপ্ট যা করে (নন-ডেস্ট্রাক্টিভ):
1. পুরনো `android\key.properties` → `android\key\key.properties.bak.<stamp>` কপি
2. নতুন keystore → `android\key\upload-keystore-v2.jks` (পুরনোটা **অক্ষত**)
3. নতুন `android\key.properties` (নতুন .jks দেখিয়ে)
4. `flutter build apk --release --split-per-abi` চালিয়ে signed APK verify করার নির্দেশ

### ⚠️ রোটেশনের প্রভাব
| পরিস্থিতি | ফল |
|---|---|
| সরাসরি APK বিতরণ (Play ছাড়া) | নতুন signature ≠ পুরনো: ইউজারকে **আগে uninstall** করে নতুন APK ইনস্টল করতে হবে (in-place update হবে না) |
| Play Store-এ AAB আপলোড করা আছে (Play App Signing) | শুধু **upload key** বদলায় — ইউজারদের কিছু করতে হয় না; Play Console → *App integrity → Upload key reset* চালান |
| Play ছাড়া AAB/APK আপলোড | অ্যাপ-সাইনিং কী বদলে যায় → updates বন্ধ হতে পারে; Play Console-এ কী রিসেট রিকোয়েস্ট করুন |

## ২. পাসওয়ার্ড কোথায় রাখবেন (ফাইলে নয়)

**উপায় ক (সুপারিশ):** এনভায়রনমেন্ট ভেরিয়েবল — `android/app/build.gradle.kts`
এখন env-কে অগ্রাধিকার দেয়:

```powershell
$env:storePassword = '<pাসওয়ার্ড>'
$env:keyPassword   = '<পাসওয়ার্ড>'
$env:keyAlias      = 'upload'
$env:storeFile     = 'C:\secrets\upload-keystore-v2.jks'
flutter build apk --release
```

**উপায় খ:** লোকাল `android/key.properties` (আগের মতোই, gitignored) — তবে
পাসওয়ার্ড কখনো কোনো `.md`/`.bat`/commit-এ লিখবেন না।

## ৩. Git history থেকে পাসওয়ার্ড মুছে ফেলা

পাসওয়ার্ড history-তে থাকলে শুধু ফাইল বদলালেই হয় না — **সব ক্লোনে history
rewrite** লাগে (force-push দরকার; টিম থাকলে আগে সবাইকে জানান)।

```bash
# ভরসা করার মতো ব্যাকআপ (mirror) আগে নিন
git clone --mirror . ../dakhila_camera_backup.git

# পদ্ধতি ১: git filter-repo (সুপারিশ)
pip install git-filter-repo
git filter-repo --replace-text <(echo 'DakhilaCam@2026==>***REMOVED***')
# চাইলে শুধু ওই ফাইল: --path PLAN-3DOC.md --replace-text ...

# পদ্ধতি ২: BFG (Java)
java -jar bfg.jar --replace-text secrets.txt dakhila_camera.git
git reflog expire --expire=now --all && git gc --prune=now --aggressive

# তারপর
git push --force --all && git push --force --tags
```
> উপায়: history rewrite এড়াতে চাইলে — পুরনো repo থেকে GitHub-এ নতুন repo
> বানিয়ে শুধু current working tree push করলেও সমস্যার সমাধান হয় (পুরনো repo
> private/archive করে রাখুন)।

## ৪. নিয়ন্ত্রণ ও ভবিষ্যৎ সুরক্ষা
- keystore + পাসওয়ার্ড **অফলাইন ২ কপি** (পেনড্রাইভ/সিল করা খাম); ক্লাউডে raw ফাইল নয়।
- `.gitignore`-এ আগে থেকেই আছে: `key.properties`, `android/key/`, `android/app/*.jks` ✅ — মাঝেমধ্যে `git status --ignored` দিয়ে যাচাই করুন।
- PR/commit হুক: `git grep -nE 'storePassword=|keyPassword=|\.jks'` (CI থাকলে analyze/test-এর সাথে চালান)।
- পাসওয়ার্ড ম্যানেজারে রেকর্ড রাখুন: মালিক, তারিখ, কবে রোটেট হয়েছে।
- Play Store-এ গেলে **Play App Signing চালু রাখুন** — app signing key Google-এর কাছে, আপনার কাছে শুধু upload key।
