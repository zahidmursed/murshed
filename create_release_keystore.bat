@echo off
setlocal
title Dakhila Camera - Release Keystore Setup

if exist "android\key.properties" (
  echo ERROR: android\key.properties ইতিমধ্যে আছে। বর্তমান keystore দিয়েই APK build হবে।
  echo নতুন keystore তৈরি করলে পুরোনো APK-এর update install হবে না।
  goto :end
)

where keytool >nul 2>nul
if errorlevel 1 (
  echo ERROR: Java keytool পাওয়া যায়নি। Flutter/Android Studio-এর JDK PATH-এ দিন।
  goto :end
)

echo.
echo এই keystore-ই ভবিষ্যতের সব APK update-এর পরিচয়।
echo এটিকে ও password নিরাপদে backup করুন; হারালে পুরোনো APK update করা যাবে না।
echo.
set /p KEY_ALIAS="Key alias (default dakhila_camera): "
if "%KEY_ALIAS%"=="" set KEY_ALIAS=dakhila_camera
set /p STORE_PASSWORD="Keystore password লিখুন: "
if "%STORE_PASSWORD%"=="" (
  echo ERROR: password খালি রাখা যাবে না।
  goto :end
)
set /p KEY_PASSWORD="Key password লিখুন (default: একই password): "
if "%KEY_PASSWORD%"=="" set KEY_PASSWORD=%STORE_PASSWORD%

echo.
echo Keystore তৈরি হচ্ছে...
keytool -genkeypair -v -keystore "android\app\upload-keystore.jks" -alias "%KEY_ALIAS%" -keyalg RSA -keysize 2048 -validity 10000 -storepass "%STORE_PASSWORD%" -keypass "%KEY_PASSWORD%" -dname "CN=Dakhila Camera, OU=Android, O=Dakhila Camera, C=BD"
if errorlevel 1 (
  echo ERROR: Keystore তৈরি হয়নি।
  goto :end
)

(
  echo storePassword=%STORE_PASSWORD%
  echo keyPassword=%KEY_PASSWORD%
  echo keyAlias=%KEY_ALIAS%
  echo storeFile=upload-keystore.jks
) > "android\key.properties"

echo.
echo সফল। android\app\upload-keystore.jks এবং android\key.properties আলাদা নিরাপদ স্থানে backup করুন।
echo এগুলো কাউকে পাঠাবেন না এবং Git-এ commit করবেন না।

:end
echo.
pause
endlocal
