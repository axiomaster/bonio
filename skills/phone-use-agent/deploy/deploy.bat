@echo off
setlocal

echo Building phone-use-harmonyos...
cmake -B build
cmake --build build --config Release

if %ERRORLEVEL% neq 0 (
    echo Build failed!
    exit /b 1
)

echo Deploying to device...

REM Stop existing process
hdc shell "killall phone-use-harmonyos" 2>nul

REM Deploy binary
hdc file send build\bin\openclaw_service /data/local/bin/phone-use-harmonyos
if %ERRORLEVEL% neq 0 (
    echo Deployment failed!
    exit /b 1
)

REM Set permissions
hdc shell "chmod +x /data/local/bin/phone-use-harmonyos"

echo.
echo Deployment complete!
echo.
echo Usage:
echo   hdc shell "/data/local/bin/phone-use-harmonyos --help"
echo   hdc shell "/data/local/bin/phone-use-harmonyos --apikey YOUR_KEY --task '打开微信'"
echo.

endlocal
