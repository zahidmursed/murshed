@echo off
setlocal
title Dakhila Camera - Rotate Release Keystore (v2)

:: ============================================================
:: Non-destructive keystore rotation.
::   old: android/key/upload-keystore.jks  + android/key.properties (backed up)
::   new: android/key/upload-keystore-v2.jks + fresh android/key.properties
:: The old keystore is NEVER deleted - remove it manually after you
:: verified the new signed APK and completed the rollout.
:: ASCII-only messages (Windows codepage safety).
:: ============================================================

if not exist "android" (
  echo ERROR: run this script from the project root (android\ folder not found).
  goto :end
)

echo.
echo ===================================================
echo   Release keystore ROTATION (v2)
echo ===================================================
echo.
echo Why: the old keystore password was committed to git history
echo      (PLAN-3DOC.md, commit around v2.0.0). See SECURITY-KEY-ROTATION.md.
echo.
echo NOTE: rotating the key changes the APK signature. Direct-APK users
echo       must uninstall the old app first. If the app was published with
echo       Play App Signing, only the upload key changes (Play Console -
echo       App integrity - Upload key reset).
echo.
set /p CONFIRM="Type ROTATE to continue: "
if /I not "%CONFIRM%"=="ROTATE" (
  echo Cancelled.
  goto :end
)

:: --- JDK keytool ---
if exist ".jdk\jdk-17.0.20.1+1\bin\keytool.exe" (
  set "KEYTOOL=.jdk\jdk-17.0.20.1+1\bin\keytool.exe"
) else (
  where keytool >nul 2>nul
  if errorlevel 1 (
    echo ERROR: keytool not found. Add your JDK/Android Studio JDK to PATH,
    echo        or place a JDK under .jdk\ in this project.
    goto :end
  )
  set "KEYTOOL=keytool"
)

:: --- inputs ---
set /p KEY_ALIAS="Key alias (default dakhila_camera_v2): "
if "%KEY_ALIAS%"=="" set KEY_ALIAS=dakhila_camera_v2

set /p STORE_PASSWORD="New keystore password (min 12 chars, not the old one): "
if "%STORE_PASSWORD%"=="" (
  echo ERROR: password cannot be empty.
  goto :end
)
if "%STORE_PASSWORD%"=="DakhilaCam@2026" (
  echo ERROR: that is the LEAKED password - choose a new one.
  goto :end
)
set /p KEY_PASSWORD="New key password (default: same as store password): "
if "%KEY_PASSWORD%"=="" set KEY_PASSWORD=%STORE_PASSWORD%

:: --- backup old properties (if any) ---
if exist "android\key.properties" (
  for /f "tokens=2 delims==" %%d in ('wmic os get localdatetime /value ^| find "="') do set "STAMP=%%d"
  set "STAMP=%STAMP:~0,8%-%STAMP:~8,6%"
  copy /Y "android\key.properties" "android\key\key.properties.bak.%STAMP%" >nul
  echo [1/4] Old key.properties backed up to android\key\key.properties.bak.%STAMP%
) else (
  echo [1/4] No existing key.properties - nothing to back up.
)

:: --- new keystore (old file untouched) ---
set "NEW_JKS=android\key\upload-keystore-v2.jks"
if exist "%NEW_JKS%" (
  echo ERROR: %NEW_JKS% already exists. Rename/remove it first.
  goto :end
)
if not exist "android\key" mkdir "android\key"
echo [2/4] Creating new keystore: %NEW_JKS%
"%KEYTOOL%" -genkeypair -v -keystore "%NEW_JKS%" -alias "%KEY_ALIAS%" -keyalg RSA -keysize 2048 -validity 10000 -storepass "%STORE_PASSWORD%" -keypass "%KEY_PASSWORD%" -dname "CN=Dakhila Camera, OU=Android, O=Dakhila Camera, C=BD"
if errorlevel 1 (
  echo ERROR: keystore creation failed.
  goto :end
)

:: --- point key.properties at the new keystore ---
(
  echo storePassword=%STORE_PASSWORD%
  echo keyPassword=%KEY_PASSWORD%
  echo keyAlias=%KEY_ALIAS%
  echo storeFile=upload-keystore-v2.jks
) > "android\key.properties"
echo [3/4] android\key.properties now points to upload-keystore-v2.jks

echo [4/4] Verifying with a signed release build...
call flutter build apk --release --split-per-abi
if errorlevel 1 (
  echo ERROR: build failed - check the output above.
  goto :end
)

echo.
echo Rotated successfully. Next steps:
echo   1) Backup upload-keystore-v2.jks AND its password OFFLINE (2 copies).
echo   2) Install the new APK on a test phone (uninstall the old one first).
echo   3) Keep upload-keystore.jks until the rollout is complete, then delete it.
echo   4) If the app is on Play with App Signing, reset the upload key in
echo      Play Console - App integrity - Upload key reset.
echo   5) Scrub git history: see SECURITY-KEY-ROTATION.md section 3.
echo.

:end
echo.
pause
endlocal