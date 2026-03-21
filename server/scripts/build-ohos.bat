@echo off
setlocal
REM Build hiclaw for HarmonyOS (aarch64-linux-ohos)
REM Requires OHOS_NDK_HOME to be set (path to OpenHarmony native SDK).
REM
REM Usage: scripts\build-ohos.bat
REM Output: build\ohos\hiclaw

if "%OHOS_NDK_HOME%"=="" (
  echo Error: OHOS_NDK_HOME is not set.
  echo Please set OHOS_NDK_HOME to the path of OpenHarmony native SDK, e.g.:
  echo   set OHOS_NDK_HOME=D:\path\to\sdk\default\openharmony\native
  exit /b 1
)

set "TOOLCHAIN=%OHOS_NDK_HOME%\build\cmake\ohos.toolchain.cmake"
set "SCRIPT_DIR=%~dp0"
set "PROJECT_ROOT=%SCRIPT_DIR%.."
set "BUILD_DIR=%PROJECT_ROOT%\build\ohos"

if not exist "%OHOS_NDK_HOME%" (
  echo Error: OHOS NDK not found at %OHOS_NDK_HOME%
  echo Set OHOS_NDK_HOME or install commandline-tools to the path above.
  exit /b 1
)
if not exist "%TOOLCHAIN%" (
  echo Error: Toolchain file not found: %TOOLCHAIN%
  exit /b 1
)

REM Find Ninja under OHOS_NDK_HOME (or SDK parent): use NDK's ninja only, no PATH
set "NINJA_EXE="
for /f "delims=" %%i in ('dir /b /s /a-d "%OHOS_NDK_HOME%\ninja.exe" 2^>nul') do set "NINJA_EXE=%%i" & goto :ninja_found
for /f "delims=" %%i in ('dir /b /s /a-d "%OHOS_NDK_HOME%\..\ninja.exe" 2^>nul') do set "NINJA_EXE=%%i" & goto :ninja_found
:ninja_found
if "%NINJA_EXE%"=="" (
  echo Error: Ninja not found under OHOS_NDK_HOME.
  echo Searched: %OHOS_NDK_HOME% and %OHOS_NDK_HOME%\..
  echo Please use an OpenHarmony/DevEco SDK that includes ninja in the native or build-tools folder.
  exit /b 1
)

echo ============================================
echo Building HiClaw for HarmonyOS
echo ============================================
echo OHOS_NDK_HOME: %OHOS_NDK_HOME%
echo Build dir:     %BUILD_DIR%
echo Ninja:         %NINJA_EXE%
echo.

REM If CMake cache was created from WSL (/mnt/...), remove it so Windows paths work
if exist "%BUILD_DIR%\CMakeCache.txt" (
  findstr /c:"/mnt/" "%BUILD_DIR%\CMakeCache.txt" >nul 2>&1 && (
    echo Removing stale CMake cache from WSL path...
    rmdir /s /q "%BUILD_DIR%" 2>nul
  )
)

if not exist "%BUILD_DIR%" mkdir "%BUILD_DIR%"
cd /d "%BUILD_DIR%"

set "CMAKE_EXTRA="
if not "%NINJA_EXE%"=="ninja" set "CMAKE_EXTRA=-DCMAKE_MAKE_PROGRAM=^"%NINJA_EXE%^""

cmake -G Ninja %CMAKE_EXTRA% -DCMAKE_TOOLCHAIN_FILE="%TOOLCHAIN%" "%PROJECT_ROOT%"
if errorlevel 1 exit /b 1

"%NINJA_EXE%"
if errorlevel 1 exit /b 1

echo.
echo ============================================
echo Build OK!
echo Binary: %BUILD_DIR%\hiclaw
echo ============================================
exit /b 0
