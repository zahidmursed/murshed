# Dakhila Camera — সার্ভার সেটআপ গাইড (XAMPP / cPanel)

**অবস্থা: ✅ তৈরি ও লাইভ-যাচাই করা** — এই পিসির XAMPP-এ (PHP 7.4.33 + MariaDB 10.4.27)
স্কিমা ইমপোর্ট করে, ইউজার বানিয়ে, সত্যিকারের API চালিয়ে **১৭টি স্বয়ংক্রিয় পরীক্ষা
১০০% পাস** করানো হয়েছে (লগইন, টোকেন-গার্ড, তালিকা-pull, delta-sync, ছবি-আপলোড,
dedup, ডাউনলোড hash-মিল, admin পরিসংখ্যান, path-traversal প্রতিরোধ)।

## ফাইল-তালিকা

| ফাইল | কাজ |
|---|---|
| `schema.sql` | ৬টি টেবিল (users, auth_tokens, students, documents, case_notes, sync_log) — **পুনরায় চালানো নিরাপদ** |
| `api/config.php` | DB সংযোগ + সাহায্যকারী ফাংশন (এখানেই পাসওয়ার্ড) |
| `api/login.php` | ইমেইল+পাসওয়ার্ড → ৬০ দিনের টোকেন |
| `api/pull.php` | ছাত্র/ডক-তালিকা delta (`since` দিলে শুধু বদলানোটা) |
| `api/push_doc.php` | ছবি-আপলোড (sha256-dedup, jpeg/png ≤১০MB) |
| `api/download_file.php` | ছবি ফেরত (টোকেন+নিবন্ধন যাচাই, path-traversal নিরাপদ) |
| `api/admin_stats.php` | admin: ক্লাসভিত্তিক অগ্রগতি + সিঙ্ক-লগ |
| `api/create_user.php` | CLI-তে admin/শিক্ষক তৈরি (শুধু টার্মিনাল থেকে চলে) |
| `api/.htaccess` | Authorization হেডার পাস + আপলোড-সীমা |
| `uploads/.htaccess` | আপলোড করা ফোল্ডারে কোনো স্ক্রিপ্ট চলবে না |
| `smoke-test.ps1` | উপরের সব কিছু স্বয়ংক্রিয়ভাবে পরীক্ষা করে |

---

## ধাপ ১ — ডাটাবেজ ও টেবিল

**উপায় ক (কমান্ড-লাইন, দ্রুততম):**
```powershell
cd D:\dakhila_camera
D:\xampp\mysql\bin\mysql.exe -u root < server\schema.sql
```

**উপায় খ (phpMyAdmin):** `http://localhost/phpmyadmin` → **Import** → `server/schema.sql` → **Go**
(আগে কোনো ডাটাবেজ সিলেক্ট করার দরকার নেই — ফাইলটি নিজেই `dakhila_camera` তৈরি করে।)

> **⚠️ গুরুত্বপূর্ণ:** এই ফাইলটি **MySQL/MariaDB-এর**। Postgres-এর (`uuid`, `timestamptz`)
> কোনো ফাইল phpMyAdmin-এ চালালে `#1064 ... MariaDB server version` এরর আসবে — সেটা
> ভুল ফাইল। পুরোনো ফাইল দিয়ে আগে চালানো হয়ে থাকলে নতুন ফাইল আবার চালালেই ঠিক হয়ে যাবে
> (`CREATE TABLE IF NOT EXISTS`, ইনডেক্স টেবিলের ভেতরে — তাই `#1061 Duplicate key`
> আর আসবে না)।

যাচাই:
```powershell
D:\xampp\mysql\bin\mysql.exe -u root dakhila_camera -e "SHOW TABLES;"
```

## ধাপ ২ — সার্ভার-কোড বসানো

`server/` ফোল্ডারের **ভেতরের সব কিছু** কপি করুন:
- **এই পিসিতে:** `D:\xampp\htdocs\dakhila\`
- **cPanel হোস্টিংয়ে:** `public_html/dakhila/`

```powershell
New-Item -ItemType Directory -Force D:\xampp\htdocs\dakhila | Out-Null
Copy-Item -Recurse -Force D:\dakhila_camera\server\* D:\xampp\htdocs\dakhila\
```

শেষ গঠন: `htdocs\dakhila\api\*.php` + `htdocs\dakhila\uploads\` (ছবি এখানে জমা হবে)।

## ধাপ ৩ — `api/config.php` যাচাই

XAMPP ডিফল্ট = `DB_USER='root'`, `DB_PASS=''` — এই পিসিতে এটাই কাজ করছে।
**cPanel/প্রোডাকশনে অবশ্যই আলাদা DB-ইউজার + শক্ত পাসওয়ার্ড দিন, আর `config.php`
ওয়েবরুটের বাইরে রাখুন।**

## ধাপ ৪ — প্রথম admin ও শিক্ষক তৈরি

XAMPP → **Shell** বাটন (বা `D:\xampp\php\php.exe` দিয়ে):
```powershell
cd D:\xampp\htdocs\dakhila\api
D:\xampp\php\php.exe create_user.php admin@madrasa.com "আপনার নাম" StrongPass123 admin
D:\xampp\php\php.exe create_user.php teacher1@madrasa.com "শিক্ষকের নাম" TeacherPass123 teacher
```
সফল হলে দেখাবে: `✓ তৈরি হয়েছে: admin@madrasa.com (admin)`

> **নোট:** শিক্ষক শুধু নিজের তোলা ছবি+তালিকা দেখতে পারে; admin সব কিছু + অনুমোদন (`is_verified`)।

## ধাপ ৫ — ছাত্রদের তালিকা সার্ভারে তোলা

ছবি আপলোড হতে হলে আগে ওই দাখিলার ছাত্র সার্ভারে থাকতে হবে (`push_doc.php` না পেলে
`NO_STUDENT` দেয়)। এখন তালিকা তোলার পথ = **phpMyAdmin → students টেবিল → Import → CSV**।

- CSV অবশ্যই **UTF-8** হতে হবে, কলাম-নাম হুবহু টেবিলের নামের মতো
  (`dakhila, stu_name, class_name, forik_no, dakhila_year, exam_year, ...`), আর **`dakhila` = PRIMARY KEY**।
- Excel থেকে সেভ করলে "CSV UTF-8" ফরম্যাট বেছে নিন, নইলে বাংলা `?` হয়ে যাবে।

> **⚠️ কনসোল দিয়ে বাংলা লিখবেন না:** `mysql -e "INSERT ... 'টেস্ট ছাত্র'"` করলে
> Windows-এর কোডপেজে বাংলা `?????` (hex `3F3F…`) হয়ে যায় — এটা আমরা লাইভে দেখেছি।
> phpMyAdmin, বা `mysql --default-character-set=utf8mb4 < file.sql` ব্যবহার করুন।

একই দাখিলা ভিন্ন বছর = **একই ব্যক্তি** (স্কিমায় বছর মাত্র তথ্য-কলাম), তাই নতুন বছরের
তালিকা ইমপোর্টে পুরোনো ছবি/ডক হারায় না (উপরে `dakhila`-ই দাঁড়িয়ে থাকে)।

## ধাপ ৬ — যাচাই (স্বয়ংক্রিয় স্মোক-টেস্ট)

```powershell
# Apache চালু থাকলে:
pwsh -File D:\dakhila_camera\server\smoke-test.ps1 `
  -Email admin@madrasa.com -Password 'StrongPass123'

# ছবি-আপলোডও পরীক্ষা করতে (দাখিলাটি students-এ থাকতে হবে):
pwsh -File D:\dakhila_camera\server\smoke-test.ps1 `
  -Email admin@madrasa.com -Password 'StrongPass123' `
  -Dakhila 554 -Photo C:\path\to\photo.jpg -DocType PHOTO
```
সব ঠিক থাকলে শেষ লাইন: `=== ফল: 17 পাস • 0 ফেল ===`

Apache ছাড়া দ্রুত পরীক্ষা:
```powershell
D:\xampp\php\php.exe -S 127.0.0.1:8123 -t D:\dakhila_camera\server     # আলাদা টার্মিনাল
pwsh -File .\server\smoke-test.ps1 -Base http://127.0.0.1:8123/api -Email ... -Password ...
```

## API সারসংক্ষেপ

| Endpoint | পদ্ধতি | কাজ |
|---|---|---|
| `api/login.php` | POST JSON | `{email,password,device_id?}` → `{token, user}` (টোকেন বৈধ ৬০ দিন) |
| `api/pull.php` | GET | `?since=YYYY-MM-DD HH:MM:SS` → `{students:[], documents:[], now}` |
| `api/push_doc.php` | POST multipart | `dakhila, doc_type(PHOTO/BIRTH/FORM), file` → `{storage_path}` বা `{skipped:true}` |
| `api/download_file.php` | GET | `?path=docs/554/BIRTH.jpg` → ছবি (টোকেন প্রয়োজন) |
| `api/admin_stats.php` | GET | admin: মোট/ছবি-তোলা/ডক + ক্লাসভিত্তিক + শেষ ২০টি সিঙ্ক |
| `create_user.php` | CLI | ইউজার তৈরি |

প্রত্যেক টোকেন-প্রয়োজনীয় কলে হেডার: `Authorization: Bearer <token>`
সার্ভারের সময়ই পরের `since` — ডিভাইস ঘড়ির ভুল হলেও sync নষ্ট হয় না।

## ট্রাবলশুটিং (যা যা লাইভে ধরা পড়েছে)

| উপসর্গ | কারণ ও সমাধান |
|---|---|
| `#1064 ... near 'uuid' / 'timestamptz'` | Postgres-এর স্কিমা phpMyAdmin-এ চালানো হয়েছে → **শুধু `server/schema.sql`** চালান |
| `#1061 Duplicate key name 'idx_...'` | পুরোনো স্কিমা-ফাইল; এখন ইনডেক্স টেবিলের ভেতরে — নতুন ফাইল আবার চালালেই ঠিক |
| `টোকেন ছাড়া 401` তবে টোকেন পাঠিয়েও 401 | Apache CGI/FastCGI-তে Authorization হেডার PHP-তে পৌঁছায় না → `api/.htaccess` (SetEnvIf) ফাইলটি রাখতে ভুলবেন না |
| লগইন পেজ/আপলোড 500, `Call to undefined function str_contains()` | PHP 8-only কোড PHP 7.4-এ — এখন সব PHP 7.4-সামঞ্জস্য (XAMPP 7.4.33-এ যাচাই করা) |
| আপলোড 10MB-এর বেশি হলে ফেল | `api/.htaccess`-এ `upload_max_filesize 12M`/`post_max_size 14M` দেওয়া আছে; cPanel-এ PHP সেটিং থেকে বাড়ান |
| বাংলা `?????` হয়ে গেল | কনসোল-কোডপেজ; phpMyAdmin বা `--default-character-set=utf8mb4` দিয়ে UTF-8 ফাইল ইমপোর্ট করুন |
| `NO_STUDENT — এই দাখিলার ছাত্র সার্ভারে নেই` | প্রথমে ধাপ ৫-এর মতো তালিকা সার্ভারে তুলুন |
| `skipped:true` এল | একই ছবি আগেই আপলোড হয়েছে (sha256 মিল) — এটাই কাঙ্ক্ষিত, ব্যান্ডউইথ বাঁচে |

## নিরাপত্তা-চেকলিস্ট (আগে পড়ুন)

1. **HTTPS ছাড়া ইন্টারনেটে খুলবেন না** — টোকেন ও ছবি খোলা যাবে। cPanel-এ ফ্রি
   Let's Encrypt; XAMPP-এ শুধু স্থানীয় টেস্টের জন্য `http` ঠিক আছে।
2. `api/config.php` — প্রোডাকশনে ওয়েবরুটের বাইরে রাখুন, শক্ত DB-পাসওয়ার্ড দিন।
3. `uploads/`-এ PHP বন্ধ (`php_flag engine off` — `.htaccess` ফাইলে দেওয়া আছে)।
4. **টোকেন ৬০ দিনে মেয়াদোত্তীর্ণ**; শিক্ষক চলে গেলে `/admin` থেকে ইউজার মুছুন
   (`auth_tokens` CASCADE-এ মুছে যাবে)।
5. **নিয়মিত ব্যাকআপ:** `D:\xampp\mysql\bin\mysqldump.exe -u root dakhila_camera > backup.sql`
   + `uploads/` ফোল্ডারের কপি। প্রোডাকশনে দিনে একবার স্বয়ংক্রিয় করুন।
6. ছবি/নাম/অভিভাবকের নম্বর = সংবেদনশীল ডেটা → প্রতিষ্ঠানের লিখিত সম্মতি নিন,
   অ্যাক্সেস কেবল দায়িত্বপ্রাপ্ত শিক্ষকদের দিন।

## এখনো যা নেই (পরের ধাপে)

| বাকি কাজ | কারণ/proposed |
|---|---|
| **ছাত্র-তালিকা সার্ভারে push** (`push_students.php`) | এখন phpMyAdmin-এ CSV ইমপোর্ট করতে হয়; S2-তে অ্যাপ থেকেই সরাসরি যাবে |
| **Flutter SyncService (S2)** | লগইন স্ক্রিন, `pull` → লোকাল DB, pending-ছবির তালিকা → `push_doc`, অফলাইন-কিউ + retry, AppBar ব্যাজ |
| **লোকাল DB v10** | `sync_state`, `server_rev`, `captured_by` কলাম (এখন স্কিমায় টেবিল প্রস্তুত) |
| **Admin Panel (S5)** | `admin_stats.php`-এর ডেটা দিয়ে ক্লাসভিত্তিক অগ্রগতি, অনুমোদন, ছবি-যাচাই |
| **sync_log লেখা** | `push` শেষে `sync_log`-এ হিসাব যোগ (এখন টেবিল ও endpoint প্রস্তুত) |