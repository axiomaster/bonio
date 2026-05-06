@echo off
REM Build paddle_ocr_plugin.dll for Windows x64
REM Requires: Visual Studio Build Tools 2022

REM Find vcvars
set "VCVARS="
if exist "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" (
  set "VCVARS=C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
)
if exist "C:\Program Files\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" (
  set "VCVARS=C:\Program Files\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
)
if exist "C:\Program Files (x86)\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" (
  set "VCVARS=C:\Program Files (x86)\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
)
if "%VCVARS%"=="" (
  echo ERROR: vcvars64.bat not found. Install Visual Studio Build Tools 2022.
  exit /b 1
)

call "%VCVARS%" >nul 2>&1
cd /d "%~dp0"

if not exist build mkdir build
cl /nologo /LD /O2 /EHsc /std:c++17 paddle_ocr_wrapper.cpp /Fe:build\paddle_ocr_plugin.dll
if errorlevel 1 exit /b 1

echo.
echo Build OK: build\paddle_ocr_plugin.dll
