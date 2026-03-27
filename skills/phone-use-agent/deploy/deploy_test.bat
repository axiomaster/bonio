@echo off
set NINJA_PATH=D:\tools\commandline-tools-windows\sdk\default\openharmony\native\build-tools\cmake\bin\ninja.exe
set BUILD_DIR=build

echo ========================================
echo [1/3] Building Test...
echo ========================================
if not exist %BUILD_DIR% mkdir %BUILD_DIR%
cd %BUILD_DIR%

if not exist build.ninja (
    echo [INFO] build.ninja not found. Running CMake...
    D:\tools\commandline-tools-windows\sdk\default\openharmony\native\build-tools\cmake\bin\cmake.exe -G Ninja -DCMAKE_MAKE_PROGRAM=%NINJA_PATH% ..
)
%NINJA_PATH% test_executor_ut
if %errorlevel% neq 0 (
    echo Build failed!
    cd ..
    exit /b %errorlevel%
)
cd ..

echo.
echo ========================================
echo [2/3] Pushing Test to Device...
echo ========================================
pushd build\bin
hdc file send test_executor_ut /data/local/tmp/test_executor_ut
if %errorlevel% neq 0 (
    echo [ERROR] Failed to push test binary!
    popd
    exit /b %errorlevel%
)
popd
hdc shell "chmod +x /data/local/tmp/test_executor_ut"

echo.
echo ========================================
echo [3/3] Running Test...
echo ========================================
hdc shell "/data/local/tmp/test_executor_ut"
