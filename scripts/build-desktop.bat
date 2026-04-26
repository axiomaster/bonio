@echo off
setlocal
REM Build Flutter desktop, bundle hiclaw, and launch.
REM Requires hiclaw.exe in server\bin\ (run build-server.bat first).
REM
REM Usage: scripts\build-desktop.bat [--clean] [--run]

set "SCRIPT_DIR=%~dp0"
set "PROJECT_ROOT=%SCRIPT_DIR%.."
set "DESKTOP_DIR=%PROJECT_ROOT%\desktop"

set "CLEAN=false"
set "RUN=false"
for %%a in (%*) do (
  if "%%a"=="--clean" set "CLEAN=true"
  if "%%a"=="--run" set "RUN=true"
)

REM Build Flutter
cd /d "%DESKTOP_DIR%"
if "%CLEAN%"=="true" (
  if exist "build\windows" rmdir /s /q "build\windows"
  echo Cleaned desktop build directory.
)

echo Building Flutter desktop...
call flutter build windows
if errorlevel 1 (
  echo ERROR: Flutter build failed.
  exit /b 1
)

REM Bundle hiclaw
echo Bundling hiclaw...
call powershell -ExecutionPolicy Bypass -File "%DESKTOP_DIR%\scripts\bundle-hiclaw.ps1"
if errorlevel 1 exit /b 1

REM Optionally launch
if "%RUN%"=="true" (
  echo Launching bonio_desktop...
  start "" "%DESKTOP_DIR%\build\windows\x64\runner\Release\bonio_desktop.exe"
)

exit /b 0
