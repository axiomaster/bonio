@echo off
setlocal
REM Build HiClaw for Windows x64 using standard CMake toolchain (Ninja + compiler in PATH).
REM Requires: CMake, Ninja, and a C++17 compiler. If using MSVC, we set up x64 env so cl.exe is 64-bit.
REM
REM Usage: scripts\build-win-x64.bat
REM Output: build\win-x64\hiclaw.exe

set "SCRIPT_DIR=%~dp0"
set "PROJECT_ROOT=%SCRIPT_DIR%.."
set "BUILD_DIR=%PROJECT_ROOT%\build\win-x64"

REM vcpkg integration (optional but recommended for mbedTLS)
REM Install: vcpkg install mbedtls:x64-windows
set "VCPKG_ROOT=D:\tools\vcpkg-2026.02.27"
set "VCPKG_TOOLCHAIN="
if exist "%VCPKG_ROOT%\scripts\buildsystems\vcpkg.cmake" (
  set "VCPKG_TOOLCHAIN=-DCMAKE_TOOLCHAIN_FILE=%VCPKG_ROOT%\scripts\buildsystems\vcpkg.cmake"
)

REM Use MSVC x64 environment so cl.exe is 64-bit and standard headers (e.g. <string>) are found.
set "VCVARS="
if exist "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" set "VCVARS=C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
if exist "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" set "VCVARS=C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
if exist "C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvars64.bat" set "VCVARS=C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvars64.bat"
if exist "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Auxiliary\Build\vcvars64.bat" set "VCVARS=C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Auxiliary\Build\vcvars64.bat"
if defined VCVARS (
  echo Setting up MSVC x64 environment...
  call "%VCVARS%"
)

REM Prefer D:\tools\ninja if present, else use ninja from PATH
set "NINJA_EXE=ninja"
if exist "D:\tools\ninja\ninja.exe" set "NINJA_EXE=D:\tools\ninja\ninja.exe"

echo ============================================
echo Building HiClaw for Windows x64
echo ============================================
echo Build dir: %BUILD_DIR%
echo.

if not exist "%BUILD_DIR%" mkdir "%BUILD_DIR%"
cd /d "%BUILD_DIR%"

REM If we just set up x64 env, reconfig so CMake uses 64-bit cl (avoids "string: No such file")
if defined VCVARS if exist "CMakeCache.txt" del "CMakeCache.txt"

set "CMAKE_EXTRA="
if not "%NINJA_EXE%"=="ninja" set "CMAKE_EXTRA=-DCMAKE_MAKE_PROGRAM=^"%NINJA_EXE%^""

cmake -G Ninja %CMAKE_EXTRA% %VCPKG_TOOLCHAIN% -DCMAKE_BUILD_TYPE=Release "%PROJECT_ROOT%"
if errorlevel 1 exit /b 1

"%NINJA_EXE%"
if errorlevel 1 exit /b 1

echo.
echo ============================================
echo Build OK!
echo Binary: %BUILD_DIR%\hiclaw.exe
echo ============================================
exit /b 0
