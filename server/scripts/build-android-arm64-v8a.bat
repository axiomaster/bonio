@echo off
setlocal EnableDelayedExpansion
REM Build hiclaw for Android (aarch64-linux-android)
REM Requires ANDROID_NDK_HOME to be set (path to Android NDK).
REM
REM Usage:
REM   set ANDROID_NDK_HOME=D:\Android\sdk\ndk\26.1.10909125
REM   scripts\build-android.bat
REM
REM Optional environment variables:
REM   ANDROID_ABI       - Target ABI (default: arm64-v8a)
REM   ANDROID_API_LEVEL - Minimum SDK version (default: 24)
REM   HICLAW_BUILD_TYPE - Release or Debug (default: Release)
REM
REM Output: build\android\{ABI}\hiclaw

if "%ANDROID_NDK_HOME%"=="" (
  echo Error: ANDROID_NDK_HOME is not set.
  echo Please set ANDROID_NDK_HOME to the path of Android NDK, e.g.:
  echo   set ANDROID_NDK_HOME=D:\Android\sdk\ndk\26.1.10909125
  echo.
  echo You can find installed NDK versions in:
  echo   %%LOCALAPPDATA%%\Android\Sdk\ndk\
  echo   or your custom SDK location.
  exit /b 1
)

REM Default settings
if "%ANDROID_ABI%"=="" set "ANDROID_ABI=arm64-v8a"
if "%ANDROID_API_LEVEL%"=="" set "ANDROID_API_LEVEL=24"
if "%HICLAW_BUILD_TYPE%"=="" set "HICLAW_BUILD_TYPE=Release"

set "TOOLCHAIN=%ANDROID_NDK_HOME%\build\cmake\android.toolchain.cmake"
set "SCRIPT_DIR=%~dp0"
set "PROJECT_ROOT=%SCRIPT_DIR%.."
set "BUILD_DIR=%PROJECT_ROOT%\build\android-%ANDROID_ABI%"

if not exist "%ANDROID_NDK_HOME%" (
  echo Error: Android NDK not found at %ANDROID_NDK_HOME%
  echo Please verify the path and install NDK if needed.
  exit /b 1
)
if not exist "%TOOLCHAIN%" (
  echo Error: Toolchain file not found: %TOOLCHAIN%
  echo The NDK installation appears incomplete.
  exit /b 1
)

REM Find CMake in NDK
set "CMAKE_EXE=%ANDROID_NDK_HOME%\toolchains\llvm\prebuilt\windows-x86_64\bin\cmake.exe"
if not exist "%CMAKE_EXE%" (
  REM Try system CMake
  where cmake >nul 2>&1
  if errorlevel 1 (
    echo Error: CMake not found. Please install CMake or use NDK's bundled CMake.
    exit /b 1
  )
  set "CMAKE_EXE=cmake"
)

REM Find Ninja in NDK
set "NINJA_EXE=%ANDROID_NDK_HOME%\toolchains\llvm\prebuilt\windows-x86_64\bin\ninja.exe"
if not exist "%NINJA_EXE%" (
  REM Try system Ninja
  where ninja >nul 2>&1
  if errorlevel 1 (
    echo Error: Ninja not found. Please install Ninja or use NDK's bundled Ninja.
    exit /b 1
  )
  set "NINJA_EXE=ninja"
)

echo ============================================
echo Building HiClaw for Android
echo ============================================
echo ANDROID_NDK_HOME:  %ANDROID_NDK_HOME%
echo ANDROID_ABI:       %ANDROID_ABI%
echo ANDROID_API_LEVEL: %ANDROID_API_LEVEL%
echo BUILD_TYPE:        %HICLAW_BUILD_TYPE%
echo Build dir:         %BUILD_DIR%
echo CMake:             %CMAKE_EXE%
echo Ninja:             %NINJA_EXE%
echo ============================================

REM Clean build directory if switching ABI
if exist "%BUILD_DIR%\CMakeCache.txt" (
  findstr /c:"ANDROID_ABI:STRING=%ANDROID_ABI%" "%BUILD_DIR%\CMakeCache.txt" >nul 2>&1
  if errorlevel 1 (
    echo Removing stale CMake cache for different ABI...
    rmdir /s /q "%BUILD_DIR%" 2>nul
  )
)

if not exist "%BUILD_DIR%" mkdir "%BUILD_DIR%"
cd /d "%BUILD_DIR%"

"%CMAKE_EXE%" -G Ninja ^
  -DCMAKE_MAKE_PROGRAM="%NINJA_EXE%" ^
  -DCMAKE_TOOLCHAIN_FILE="%TOOLCHAIN%" ^
  -DANDROID_ABI="%ANDROID_ABI%" ^
  -DANDROID_PLATFORM=android-%ANDROID_API_LEVEL% ^
  -DANDROID_STL=c++_static ^
  -DCMAKE_BUILD_TYPE=%HICLAW_BUILD_TYPE% ^
  -DHICLAW_GATEWAY_BACKEND=websocketpp ^
  "%PROJECT_ROOT%"

if errorlevel 1 (
  echo.
  echo Error: CMake configuration failed.
  exit /b 1
)

"%NINJA_EXE%"
if errorlevel 1 (
  echo.
  echo Error: Build failed.
  exit /b 1
)

echo.
echo ============================================
echo Build OK!
echo Binary: %BUILD_DIR%\hiclaw
echo ============================================

REM Copy to bin/
set "BIN_DIR=%PROJECT_ROOT%\bin"
if not exist "%BIN_DIR%" mkdir "%BIN_DIR%"
copy /y "%BUILD_DIR%\hiclaw" "%BIN_DIR%\hiclaw" >nul
echo Copied to %BIN_DIR%\hiclaw

exit /b 0
