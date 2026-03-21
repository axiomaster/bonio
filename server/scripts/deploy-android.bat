@echo off
setlocal EnableDelayedExpansion
REM Deploy hiclaw to Android device via adb
REM
REM Usage:
REM   scripts\deploy-android.bat [ABI]
REM   scripts\deploy-android.bat arm64-v8a
REM
REM If ABI is not specified, uses arm64-v8a (most common for modern devices)

set "ABI=%1"
if "%ABI%"=="" set "ABI=arm64-v8a"

set "SCRIPT_DIR=%~dp0"
set "PROJECT_ROOT=%SCRIPT_DIR%.."
set "BUILD_DIR=%PROJECT_ROOT%\build-android-%ABI%"
set "BINARY=%BUILD_DIR%\hiclaw"
set "REMOTE_PATH=/data/local/tmp/hiclaw"

REM Check if binary exists
if not exist "%BINARY%" (
  echo Error: Binary not found at %BINARY%
  echo Please build first: scripts\build-android.bat
  echo Make sure ANDROID_ABI=%ABI% was used.
  exit /b 1
)

REM Check if adb is available
where adb >nul 2>&1
if errorlevel 1 (
  echo Error: adb not found in PATH.
  echo Please add Android SDK platform-tools to PATH.
  exit /b 1
)

REM Check if device is connected
adb get-state >nul 2>&1
if errorlevel 1 (
  echo Error: No Android device connected or unauthorized.
  echo Please connect a device and authorize USB debugging.
  exit /b 1
)

echo ============================================
echo Deploying HiClaw to Android device
echo ============================================
echo ABI:         %ABI%
echo Binary:      %BINARY%
echo Remote path: %REMOTE_PATH%
echo ============================================

echo Pushing binary...
adb push "%BINARY%" "%REMOTE_PATH%"
if errorlevel 1 (
  echo Error: Failed to push binary.
  exit /b 1
)

echo Setting executable permission...
adb shell chmod +x "%REMOTE_PATH%"

echo.
echo Testing binary...
adb shell "%REMOTE_PATH% --version"
if errorlevel 1 (
  echo Warning: Binary executed but may have issues.
) else (
  echo.
  echo ============================================
  echo Deploy OK!
  echo.
  echo To run gateway:
  echo   adb shell
  echo   %REMOTE_PATH% gateway --port 18789
  echo ============================================
)
exit /b 0
