@echo off
setlocal
REM Build hiclaw server only.
REM
REM Usage: scripts\build-server.bat [--clean]

set "SCRIPT_DIR=%~dp0"
set "PROJECT_ROOT=%SCRIPT_DIR%.."
set "SERVER_DIR=%PROJECT_ROOT%\server"

set "CLEAN=false"
for %%a in (%*) do if "%%a"=="--clean" set "CLEAN=true"

if "%CLEAN%"=="true" (
  if exist "%SERVER_DIR%\build\win-amd64" rmdir /s /q "%SERVER_DIR%\build\win-amd64"
  echo Cleaned server build directory.
)

call "%SERVER_DIR%\scripts\build-win-amd64.bat"
exit /b %errorlevel%
