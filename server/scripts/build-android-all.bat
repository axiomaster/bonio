@echo off
setlocal EnableDelayedExpansion
REM Build hiclaw for all common Android ABIs
REM Requires ANDROID_NDK_HOME to be set.
REM
REM Usage:
REM   set ANDROID_NDK_HOME=D:\Android\sdk\ndk\26.1.10909125
REM   scripts\build-android-all.bat
REM
REM Builds: arm64-v8a, armeabi-v7a, x86_64
REM Output: build\android\{ABI}\hiclaw

if "%ANDROID_NDK_HOME%"=="" (
  echo Error: ANDROID_NDK_HOME is not set.
  echo Please set ANDROID_NDK_HOME to the path of Android NDK.
  exit /b 1
)

set "SCRIPT_DIR=%~dp0"
set "PROJECT_ROOT=%SCRIPT_DIR%.."
set "SUCCESS_COUNT=0"
set "FAIL_COUNT=0"

echo ============================================
echo Building HiClaw for all Android ABIs
echo ============================================

for %%A in (arm64-v8a armeabi-v7a x86_64) do (
  echo.
  echo [Building %%A]
  echo ----------------------------------------
  set "ANDROID_ABI=%%A"
  call "%SCRIPT_DIR%build-android.bat"
  if !errorlevel! equ 0 (
    set /a SUCCESS_COUNT+=1
    echo [%%A] Build succeeded.
  ) else (
    set /a FAIL_COUNT+=1
    echo [%%A] Build FAILED.
  )
)

echo.
echo ============================================
echo Build Summary
echo ============================================
echo Succeeded: %SUCCESS_COUNT%
echo Failed:    %FAIL_COUNT%
echo.

if %FAIL_COUNT% gtr 0 (
  echo Some builds failed. Check the output above.
  exit /b 1
)

echo All builds completed successfully!
echo Binaries are in:
for %%A in (arm64-v8a armeabi-v7a x86_64) do (
  echo   %PROJECT_ROOT%\build\android\%%A\hiclaw
)
exit /b 0
