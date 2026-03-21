@echo off
setlocal
REM Push hiclaw to device and verify. Requires hdc in PATH.

set "SCRIPT_DIR=%~dp0"
set "PROJECT_ROOT=%SCRIPT_DIR%.."
set "HICLAW=%PROJECT_ROOT%\hiclaw"
set "BINARY=%HICLAW%\build-ohos\hiclaw"

if not exist "%BINARY%" (
  echo Error: Binary not found. Run scripts\build-ohos.bat first.
  exit /b 1
)

echo Pushing HiClaw to device /data/local/bin ...
hdc file send "%BINARY%" /data/local/bin/
if errorlevel 1 (
  echo hdc file send failed. Is device connected and hdc in PATH?
  exit /b 1
)

echo Making executable and running --version ...
hdc shell "chmod +x /data/local/bin/hiclaw && /data/local/bin/hiclaw --version"
if errorlevel 1 (
  echo hdc shell or hiclaw run failed.
  exit /b 1
)

echo.
echo Deploy and verify OK.
exit /b 0
