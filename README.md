
# Dakhila Camera - Flutter App

### উদ্দেশ্য
ক্যামেরা দিয়ে ছবি তুললে DAKHILA কলামের ভ্যালু দিয়ে ছবি সেভ হবে। যেমন 281.jpg

### সেটআপ
1. flutter pub get
2. flutter run

### ফিচার
- assets/Data_basic.json থেকে অটো লোড
- ফরিক নং দিয়ে ফিল্টার
- দাখিলা / নাম দিয়ে সার্চ
- Serial Mode: 281 তুললে অটো 282 তে যাবে
- Passport Mode: 600x800 (3:4) crop
- Original Mode: যেমন তোলা তেমন সেভ

### সেভ লোকেশন
Android/data/com.example.dakhila_camera/files/DakhilaCamera/281.jpg
পরে File Manager থেকে Pictures/DakhilaCamera তে কপি করে নিতে পারো।

### Permission
AndroidManifest.xml এ CAMERA permission add করতে হবে।
