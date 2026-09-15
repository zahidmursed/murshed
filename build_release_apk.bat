@echo off
setlocal
title Dakhila Camera - Release APK Builder

echo.
echo ===============================================
echo   Dakhila Camera - নতুন Release APK তৈরি
echo ===============================================
echo.

set /p BUILD_NUMBER="নতুন Android build number লিখুন (যেমন 17): "
if "%BUILD_NUMBER%"=="" (
  echo ERROR: Update APK-এর জন্য build number আবশ্যক।
  goto :failed
)
echo %BUILD_NUMBER%| findstr /r "^[0-9][0-9]*$" >nul
if errorlevel 1 (
  echo ERROR: build number শুধু সংখ্যা হতে হবে।
  goto :failed
)
if not exist "android\key.properties" (
  echo ERROR: Release keystore পাওয়া যায়নি। আগে create_release_keystore.bat চালান।
  goto :failed
)

where flutter >nul 2>nul
if errorlevel 1 (
  echo ERROR: Flutter পাওয়া যায়নি। Flutter SDK-এর bin ফোল্ডার PATH-এ যোগ করুন।
  goto :failed
)

echo [1/3] পুরনো build files পরিষ্কার করা হচ্ছে...
call flutter clean
if errorlevel 1 goto :failed

echo.
echo [2/3] Dependencies আপডেট করা হচ্ছে...
call flutter pub get
if errorlevel 1 goto :failed

echo.
echo [3/3] Release APK তৈরি করা হচ্ছে...
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
