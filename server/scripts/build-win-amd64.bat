@echo off
setlocal
REM Build HiClaw for Windows x64 using Visual Studio 2022 generator.
REM Requires: CMake and Visual Studio 2022 (BuildTools/Community/Professional/Enterprise).
REM
REM Usage: scripts\build-win-amd64.bat
REM Output: build\win-amd64\Release\hiclaw.exe

set "SCRIPT_DIR=%~dp0"
set "PROJECT_ROOT=%SCRIPT_DIR%.."

REM Resolve to absolute paths
for %%I in ("%PROJECT_ROOT%") do set "PROJECT_ROOT=%%~fI"
set "BUILD_DIR=%PROJECT_ROOT%\build\win-amd64"

echo ============================================
echo Building HiClaw for Windows x64
echo ============================================
echo Build dir: %BUILD_DIR%
echo.

if not exist "%BUILD_DIR%" mkdir "%BUILD_DIR%"

REM Clean stale cache
if exist "%BUILD_DIR%\CMakeCache.txt" del "%BUILD%\CMakeCache.txt"

cmake -S "%PROJECT_ROOT%" -B "%BUILD_DIR%" -G "Visual Studio 17 2022" -A x64 -DHICLAW_GATEWAY_BACKEND=websocketpp
if errorlevel 1 (
  echo ERROR: CMake configuration failed.
  exit /b 1
)

cmake --build "%BUILD_DIR%" --config Release
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
copy /y "%BUILD_DIR%\Release\hiclaw.exe" "%BIN_DIR%\hiclaw.exe" >nul
echo Copied to %BIN_DIR%\hiclaw.exe

exit /b 0
