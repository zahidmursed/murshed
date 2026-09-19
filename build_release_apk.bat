@echo off
setlocal
title Dakhila Camera - Release APK Builder

echo.
echo ===============================================
echo   Dakhila Camera - নতুন Release APK তৈরি
echo ===============================================
echo.

set BUILD_NUMBER=
echo [1/4] pubspec.yaml থেকে build number স্বয়ংক্রিয়ভাবে বাড়ানো হচ্ছে...
for /f "usebackq delims=" %%N in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0increment_build_number.ps1"`) do set BUILD_NUMBER=%%N
if "%BUILD_NUMBER%"=="" (
  echo ERROR: build number পাওয়া যায়নি। pubspec.yaml-এ 'version: x.y.z+N' আছে কিনা দেখুন।
  goto :failed
)
echo ব্যবহৃত build number: %BUILD_NUMBER%
if not exist "android\key.properties" (
  echo ERROR: Release keystore পাওয়া যায়নি। আগে create_release_keystore.bat চালান।
  goto :failed
)

where flutter >nul 2>nul
if errorlevel 1 (
  echo ERROR: Flutter পাওয়া যায়নি। Flutter SDK-এর bin ফোল্ডার PATH-এ যোগ করুন।
  goto :failed
)

echo [2/4] পুরনো build files পরিষ্কার করা হচ্ছে...
call flutter clean
if errorlevel 1 goto :failed

echo.
echo [3/4] Dependencies আপডেট করা হচ্ছে...
call flutter pub get
if errorlevel 1 goto :failed

echo.
echo [4/4] Release APK তৈরি করা হচ্ছে...
call flutter build apk --release --split-per-abi --build-number=%BUILD_NUMBER%
if errorlevel 1 goto :failed

echo.
echo সফলভাবে নতুন APK তৈরি হয়েছে:
echo build\app\outputs\flutter-apk\app-armeabi-v7a-release.apk  ^(বেশিরভাগ 32-bit ফোন^)
echo build\app\outputs\flutter-apk\app-arm64-v8a-release.apk    ^(বেশিরভাগ নতুন ফোন^)
echo build\app\outputs\flutter-apk\app-x86_64-release.apk       ^(emulator^)
echo.
echo নতুন Android ফোনের জন্য সাধারণত app-arm64-v8a-release.apk ব্যবহার করুন।
echo আগের APK-এর চেয়ে বড় build number ব্যবহার করুন, নইলে update install হবে না।
goto :end

:failed
echo.
echo APK তৈরি হয়নি। উপরের error message দেখে সমস্যাটি সমাধান করে আবার চালান।

:end
echo.
pause
endlocal
