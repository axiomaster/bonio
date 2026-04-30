@echo off
setlocal EnableDelayedExpansion
REM Build Flutter desktop, bundle hiclaw, and launch.
REM Requires hiclaw.exe in server\bin\ (run build-server.bat first).
REM
REM Usage: scripts\build-desktop.bat [--clean] [--run] [--ninja]
REM
REM   --clean    Clean build directory before building
REM   --run      Launch after build
REM   --ninja    Use Ninja instead of Visual Studio generator (avoids .vcxproj)
REM             Requires: Ninja in PATH + VS Build Tools (or MSVC toolchain)

set "SCRIPT_DIR=%~dp0"
set "PROJECT_ROOT=%SCRIPT_DIR%.."
set "DESKTOP_DIR=%PROJECT_ROOT%\desktop"

set "CLEAN=false"
set "RUN=false"
set "USE_NINJA=false"
for %%a in (%*) do (
  if "%%a"=="--clean" set "CLEAN=true"
  if "%%a"=="--run" set "RUN=true"
  if "%%a"=="--ninja" set "USE_NINJA=true"
)

REM Build Flutter
cd /d "%DESKTOP_DIR%"
if "%CLEAN%"=="true" (
  if exist "build\windows" rmdir /s /q "build\windows"
  echo Cleaned desktop build directory.
)

if "%USE_NINJA%"=="true" (
  echo.
  echo ============================================
  echo Building with Ninja (no Visual Studio)
  echo ============================================

  REM Check for Ninja
  where ninja >nul 2>&1
  if errorlevel 1 (
    echo ERROR: Ninja not found in PATH.
    echo Install: choco install ninja  or  download from https://github.com/ninja-build/ninja/releases
    exit /b 1
  )

  REM Prepend our cmake wrapper to PATH so Flutter uses Ninja
  set "PATH=%DESKTOP_DIR%\scripts;%PATH%"

  REM Flutter needs the MSVC toolchain (cl.exe, Windows SDK).
  REM If vcvars64.bat hasn't been run, try to find it from VS Build Tools.
  where cl.exe >nul 2>&1
  if errorlevel 1 (
    REM Try to locate vcvars64.bat — check (x86) paths first (default VS install location)
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
    ) else (
      echo WARNING: cl.exe not found. You need Visual Studio Build Tools 2022
      echo          with "Desktop development with C++" workload.
      echo Download: https://visualstudio.microsoft.com/downloads/#build-tools-for-visual-studio-2022
    )
  )
)

echo Building Flutter desktop...
call flutter build windows
if errorlevel 1 (
  echo ERROR: Flutter build failed.
  exit /b 1
)

REM Ninja install step (VS runs install automatically via CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD)
if "%USE_NINJA%"=="true" (
  echo Running cmake --install for Ninja build...
  cmake --install "%DESKTOP_DIR%\build\windows\x64" --config Release
  if errorlevel 1 (
    echo ERROR: cmake --install failed.
    exit /b 1
  )
)

REM Bundle hiclaw
echo Bundling hiclaw...
call powershell -ExecutionPolicy Bypass -File "%DESKTOP_DIR%\scripts\bundle-hiclaw.ps1"
if errorlevel 1 exit /b 1

REM Optionally launch
if "%RUN%"=="true" (
  REM Try Ninja output path first, then VS path
  if exist "%DESKTOP_DIR%\build\windows\x64\runner\bonio_desktop.exe" (
    set "EXE_PATH=%DESKTOP_DIR%\build\windows\x64\runner\bonio_desktop.exe"
  ) else (
    set "EXE_PATH=%DESKTOP_DIR%\build\windows\x64\runner\Release\bonio_desktop.exe"
  )
  echo Launching bonio_desktop...
  start "" "!EXE_PATH!"
)

exit /b 0
