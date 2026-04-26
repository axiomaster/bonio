@echo off
setlocal
REM Build HiClaw for Windows x64 using CMake + NMake (MSVC).
REM Requires: CMake and Visual Studio 2022 (BuildTools/Community/Professional/Enterprise).
REM
REM Usage: scripts\build-win-amd64.bat
REM Output: build\win-amd64\hiclaw.exe

set "SCRIPT_DIR=%~dp0"
set "PROJECT_ROOT=%SCRIPT_DIR%.."

REM Resolve to absolute paths
for %%I in ("%PROJECT_ROOT%") do set "PROJECT_ROOT=%%~fI"
set "BUILD_DIR=%PROJECT_ROOT%\build\win-amd64"

REM Use MSVC x64 environment
set "VCVARS="
if exist "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" set "VCVARS=C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
if exist "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" set "VCVARS=C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
if exist "C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvars64.bat" set "VCVARS=C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvars64.bat"
if exist "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Auxiliary\Build\vcvars64.bat" set "VCVARS=C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Auxiliary\Build\vcvars64.bat"

if not defined VCVARS (
  echo ERROR: Visual Studio 2022 not found. Install Build Tools or any VS 2022 edition.
  exit /b 1
)

echo Setting up MSVC x64 environment...
call "%VCVARS%"

echo ============================================
echo Building HiClaw for Windows x64 (NMake)
echo ============================================
echo Build dir: %BUILD_DIR%
echo.

if not exist "%BUILD_DIR%" mkdir "%BUILD_DIR%"
cd /d "%BUILD_DIR%"

REM Clean CMake cache if re-configuring
if exist "CMakeCache.txt" del "CMakeCache.txt"

cmake -G "NMake Makefiles" -DCMAKE_BUILD_TYPE=Release -DHICLAW_GATEWAY_BACKEND=websocketpp "%PROJECT_ROOT%"
if errorlevel 1 (
  echo ERROR: CMake configuration failed.
  exit /b 1
)

nmake
if errorlevel 1 (
  echo ERROR: Build failed.
  exit /b 1
)

echo.
echo ============================================
echo Build OK!
echo Binary: %BUILD_DIR%\hiclaw.exe
echo ============================================

REM Copy to bin/
set "BIN_DIR=%PROJECT_ROOT%\bin"
if not exist "%BIN_DIR%" mkdir "%BIN_DIR%"
copy /y "%BUILD_DIR%\hiclaw.exe" "%BIN_DIR%\hiclaw.exe" >nul
echo Copied to %BIN_DIR%\hiclaw.exe

exit /b 0
