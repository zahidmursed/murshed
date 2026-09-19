@echo off
setlocal
title Dakhila Camera - Trial APK Builder

echo.
echo ===================================================
echo   Dakhila Camera - সময়সীমাবদ্ধ Trial APK তৈরি
echo ===================================================
echo.
set /p TRIAL_DAYS="ট্রায়ালের দিন লিখুন (30 বা 60, default 30): "
if "%TRIAL_DAYS%"=="" set TRIAL_DAYS=30
if not "%TRIAL_DAYS%"=="30" if not "%TRIAL_DAYS%"=="60" (
  echo ERROR: শুধু 30 অথবা 60 দিন দেওয়া যাবে।
  goto :failed
)
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

echo.
echo [2/4] পুরনো build files পরিষ্কার করা হচ্ছে...
call flutter clean
if errorlevel 1 goto :failed

echo.
echo [3/4] Dependencies আপডেট করা হচ্ছে...
call flutter pub get
if errorlevel 1 goto :failed

echo.
echo [4/4] %TRIAL_DAYS%-দিনের Trial APK তৈরি করা হচ্ছে...
call flutter build apk --release --split-per-abi --build-number=%BUILD_NUMBER% --dart-define=TRIAL_DAYS=%TRIAL_DAYS%
if errorlevel 1 goto :failed

set OUTPUT_DIR=build\app\outputs\flutter-apk\trial-%TRIAL_DAYS%-days
if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"
copy /Y "build\app\outputs\flutter-apk\app-armeabi-v7a-release.apk" "%OUTPUT_DIR%\dakhila-camera-trial-%TRIAL_DAYS%-days-armeabi-v7a.apk" >nul
copy /Y "build\app\outputs\flutter-apk\app-arm64-v8a-release.apk" "%OUTPUT_DIR%\dakhila-camera-trial-%TRIAL_DAYS%-days-arm64-v8a.apk" >nul
copy /Y "build\app\outputs\flutter-apk\app-x86_64-release.apk" "%OUTPUT_DIR%\dakhila-camera-trial-%TRIAL_DAYS%-days-x86_64.apk" >nul

echo.
echo সফলভাবে Trial APK তৈরি হয়েছে:
echo %OUTPUT_DIR%
echo.
echo নতুন Android ফোনের জন্য arm64-v8a APK পাঠান।
echo ট্রায়াল প্রথমবার অ্যাপ চালু হওয়ার দিন থেকে গণনা শুরু হবে।
goto :end

:failed
echo.
echo Trial APK তৈরি হয়নি। উপরের error message দেখে আবার চালান।

:end
echo.
pause
endlocal
