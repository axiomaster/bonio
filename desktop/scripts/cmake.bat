@echo off
REM cmake.bat shim — delegates to cmake-wrapper.ps1 which replaces VS generator with Ninja.
REM Place this directory in PATH before the real cmake so Flutter picks it up.
set "SCRIPT_DIR=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%cmake-wrapper.ps1" %*
exit /b %ERRORLEVEL%
