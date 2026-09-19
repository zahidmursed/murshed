@echo off
setlocal
title Dakhila Camera - Universal APK Builder

echo.
echo ===============================================
echo   Dakhila Camera - Universal Release APK তৈরি
echo   (এক ফাইলেই সব ফোনে চলবে)
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
echo [4/4] Universal Release APK তৈরি করা হচ্ছে (সব ABI এক ফাইলে)...
call flutter build apk --release --build-number=%BUILD_NUMBER%
if errorlevel 1 goto :failed

for /f "tokens=2 delims= " %%V in ('findstr /b version: pubspec.yaml') do set APP_VERSION=%%V
if not exist "build\app\outputs\flutter-apk\app-release.apk" (
  echo ERROR: app-release.apk পাওয়া যায়নি। উপরের build log দেখুন।
  goto :failed
)
copy /Y "build\app\outputs\flutter-apk\app-release.apk" "build\app\outputs\flutter-apk\dakhila-camera-v%APP_VERSION%-universal.apk" >nul

echo.
echo সফলভাবে Universal APK তৈরি হয়েছে:
echo build\app\outputs\flutter-apk\dakhila-camera-v%APP_VERSION%-universal.apk
echo.
echo এই এক ফাইলই সব Android ফোনে (32-bit, 64-bit) ইনস্টল হবে।
echo Split APK-এর চেয়ে ফাইল বড় হবে; ফোনের আর্কিটেকচার নিশ্চিত থাকলে build_release_apk.bat-এর arm64-v8a ফাইল পাঠান।
echo আগের APK-এর চেয়ে বড় build number ব্যবহার করুন, নইলে update install হবে না।
goto :end

:failed
echo.
echo APK তৈরি হয়নি। উপরের error message দেখে সমস্যাটি সমাধান করে আবার চালান।

:end
echo.
pause
endlocal
