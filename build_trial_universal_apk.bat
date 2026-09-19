@echo off
setlocal
title Dakhila Camera - Universal Trial APK Builder

echo.
echo ===================================================
echo   Dakhila Camera - Universal Trial APK তৈরি
echo   (এক ফাইলেই সব ফোনে চলবে)
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
echo [4/4] %TRIAL_DAYS%-দিনের Universal Trial APK তৈরি করা হচ্ছে (সব ABI এক ফাইলে)...
call flutter build apk --release --build-number=%BUILD_NUMBER% --dart-define=TRIAL_DAYS=%TRIAL_DAYS%
if errorlevel 1 goto :failed

for /f "tokens=2 delims= " %%V in ('findstr /b version: pubspec.yaml') do set APP_VERSION=%%V
if not exist "build\app\outputs\flutter-apk\app-release.apk" (
  echo ERROR: app-release.apk পাওয়া যায়নি। উপরের build log দেখুন।
  goto :failed
)
set OUTPUT_FILE=build\app\outputs\flutter-apk\dakhila-camera-trial-%TRIAL_DAYS%-days-v%APP_VERSION%-universal.apk
copy /Y "build\app\outputs\flutter-apk\app-release.apk" "%OUTPUT_FILE%" >nul

echo.
echo সফলভাবে Universal Trial APK তৈরি হয়েছে:
echo %OUTPUT_FILE%
echo.
echo এই এক ফাইলই সব Android ফোনে (32-bit, 64-bit) ইনস্টল হবে।
echo ট্রায়াল প্রথমবার অ্যাপ চালু হওয়ার দিন থেকে গণনা শুরু হবে।
goto :end

:failed
echo.
echo Trial APK তৈরি হয়নি। উপরের error message দেখে আবার চালান।

:end
echo.
pause
endlocal
