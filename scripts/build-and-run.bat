@echo off
setlocal EnableDelayedExpansion
REM Build hiclaw + Flutter desktop, bundle, and launch.
REM
REM Usage:
REM   scripts\build-and-run.bat               Build server & desktop, then run
REM   scripts\build-and-run.bat --skip-server  Skip server build
REM   scripts\build-and-run.bat --skip-desktop Skip desktop build
REM   scripts\build-and-run.bat --clean        Clean build before building
REM   scripts\build-and-run.bat --ninja        Use Ninja instead of VS generator

set "SCRIPT_DIR=%~dp0"
set "PROJECT_ROOT=%SCRIPT_DIR%.."
set "SERVER_DIR=%PROJECT_ROOT%\server"
set "DESKTOP_DIR=%PROJECT_ROOT%\desktop"

set "SKIP_SERVER=false"
set "SKIP_DESKTOP=false"
set "CLEAN=false"
set "USE_NINJA=false"

for %%a in (%*) do (
  if "%%a"=="--skip-server" set "SKIP_SERVER=true"
  if "%%a"=="--skip-desktop" set "SKIP_DESKTOP=true"
  if "%%a"=="--clean" set "CLEAN=true"
  if "%%a"=="--ninja" set "USE_NINJA=true"
)

REM ========== Step 0: Kill running hiclaw ==========
echo Killing any running hiclaw processes...
taskkill /f /im hiclaw.exe >nul 2>&1
echo Done.

REM ========== Step 1: Build hiclaw ==========
if "%SKIP_SERVER%"=="true" (
  echo [SKIP] Server build skipped.
) else (
  echo ============================================
  echo [1/3] Building hiclaw server...
  echo ============================================
  if "%CLEAN%"=="true" (
    if exist "%SERVER_DIR%\build\win-amd64" rmdir /s /q "%SERVER_DIR%\build\win-amd64"
    echo Cleaned server build directory.
  )
  call "%SERVER_DIR%\scripts\build-win-amd64.bat"
  if errorlevel 1 (
    echo ERROR: hiclaw build failed.
    exit /b 1
  )
)

REM ========== Step 2: Build Flutter desktop ==========
if "%SKIP_DESKTOP%"=="true" (
  echo [SKIP] Desktop build skipped.
) else (
  echo.
  echo ============================================
  echo [2/3] Building Flutter desktop...
  echo ============================================
  cd /d "%DESKTOP_DIR%"
  if "%CLEAN%"=="true" (
    if exist "build\windows" rmdir /s /q "build\windows"
    echo Cleaned desktop build directory.
  )
  if "%USE_NINJA%"=="true" (
    echo Using Ninja generator (no Visual Studio)
    REM Prepend cmake wrapper to PATH so Flutter calls Ninja via our shim
    set "PATH=%DESKTOP_DIR%\scripts;!PATH!"
    REM Ensure MSVC toolchain is available (cl.exe, Windows SDK)
    where cl.exe >nul 2>&1
    if errorlevel 1 (
      if exist "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" (
        echo Setting up MSVC environment from VS Build Tools...
        call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1
      ) else if exist "C:\Program Files (x86)\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" (
        echo Setting up MSVC environment from VS Community...
        call "C:\Program Files (x86)\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1
      ) else if exist "C:\Program Files (x86)\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvars64.bat" (
        echo Setting up MSVC environment from VS Professional...
        call "C:\Program Files (x86)\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1
      ) else if exist "C:\Program Files\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" (
        echo Setting up MSVC environment from VS BuildTools...
        call "C:\Program Files\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1
      ) else if exist "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" (
        echo Setting up MSVC environment from VS Community...
        call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1
      ) else if exist "C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvars64.bat" (
        echo Setting up MSVC environment from VS Professional...
        call "C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1
      )
    )
  )
  call flutter build windows
  if errorlevel 1 (
    echo ERROR: Flutter build failed.
    exit /b 1
  )
)

REM ========== Step 2.5: Ninja install step ==========
REM Ninja (single-config) doesn't run install automatically during build.
REM Run it now to copy flutter_windows.dll, assets, etc. next to the exe.
if "%USE_NINJA%"=="true" (
  echo.
  echo ============================================
  echo [Ninja] Running cmake --install...
  echo ============================================
  cmake --install "%DESKTOP_DIR%\build\windows\x64" --config Release
  if errorlevel 1 (
    echo ERROR: cmake --install failed.
    exit /b 1
  )
)

REM ========== Step 3: Bundle hiclaw into build output ==========
echo.
  echo ============================================
echo [3/3] Bundling hiclaw into desktop...
echo ============================================
call powershell -ExecutionPolicy Bypass -File "%DESKTOP_DIR%\scripts\bundle-hiclaw.ps1"
if errorlevel 1 (
  echo ERROR: Bundle failed. Ensure hiclaw.exe exists in server\bin\
  exit /b 1
)

REM ========== Step 4: Launch ==========
REM Try Ninja output path first (no config subdir), then VS path
if exist "%DESKTOP_DIR%\build\windows\x64\runner\bonio_desktop.exe" (
  set "RUN_DIR=%DESKTOP_DIR%\build\windows\x64\runner"
) else (
  set "RUN_DIR=%DESKTOP_DIR%\build\windows\x64\runner\Release"
)
echo.
echo ============================================
echo Launching bonio_desktop...
echo ============================================
cd /d "%RUN_DIR%"
start bonio_desktop.exe
echo Done.
exit /b 0
