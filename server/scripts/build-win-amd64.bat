@echo off
setlocal EnableDelayedExpansion
REM Build HiClaw for Windows x64.
REM Auto-detects Ninja if available, falls back to Visual Studio generator.
REM Requires: CMake + either Ninja (recommended) or Visual Studio 2022 BuildTools.
REM
REM Usage: scripts\build-win-amd64.bat
REM Output: build\win-amd64\hiclaw.exe (Ninja) or build\win-amd64\Release\hiclaw.exe (VS)

set "SCRIPT_DIR=%~dp0"
set "PROJECT_ROOT=%SCRIPT_DIR%.."

REM Resolve to absolute paths
for %%I in ("%PROJECT_ROOT%") do set "PROJECT_ROOT=%%~fI"
set "BUILD_DIR=%PROJECT_ROOT%\build\win-amd64"

echo ============================================
echo Building HiClaw for Windows x64
echo ============================================

REM Detect generator: prefer Ninja, fall back to VS
where ninja >nul 2>&1
if errorlevel 1 (
  set "GENERATOR=Visual Studio 17 2022"
  set "GEN_ARGS=-A x64"
  set "BUILD_CMD=cmake --build "%BUILD_DIR%" --config Release"
  set "EXE_PATH=%BUILD_DIR%\Release\hiclaw.exe"
  echo Generator: Visual Studio 17 2022 ^(Ninja not found^)
) else (
  set "GENERATOR=Ninja"
  set "GEN_ARGS=-DCMAKE_BUILD_TYPE=Release"
  set "BUILD_CMD=cmake --build "%BUILD_DIR%""
  set "EXE_PATH=%BUILD_DIR%\hiclaw.exe"
  echo Generator: Ninja

  REM Ensure MSVC toolchain is available (cl.exe)
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
      echo Setting up MSVC environment from VS Build Tools...
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

echo Build dir: %BUILD_DIR%
echo.

if not exist "%BUILD_DIR%" mkdir "%BUILD_DIR%"

REM Clean stale cache when switching generators
if exist "%BUILD_DIR%\CMakeCache.txt" del "%BUILD_DIR%\CMakeCache.txt"

cmake -S "%PROJECT_ROOT%" -B "%BUILD_DIR%" -G "!GENERATOR!" !GEN_ARGS! -DHICLAW_GATEWAY_BACKEND=websocketpp
if errorlevel 1 (
  echo ERROR: CMake configuration failed.
  exit /b 1
)

!BUILD_CMD!
if errorlevel 1 (
  echo ERROR: Build failed.
  exit /b 1
)

echo.
echo ============================================
echo Build OK!
echo ============================================

REM Copy to bin/
set "BIN_DIR=%PROJECT_ROOT%\bin"
if not exist "%BIN_DIR%" mkdir "%BIN_DIR%"
copy /y "!EXE_PATH!" "%BIN_DIR%\hiclaw.exe" >nul
echo Copied to %BIN_DIR%\hiclaw.exe

exit /b 0
