@echo off
setlocal EnableDelayedExpansion
REM Check build environment for HiClaw Android compilation
REM
REM Usage: scripts\check-env.bat

echo ============================================
echo HiClaw Build Environment Check
echo ============================================
echo.

REM Check for Android NDK
echo [Android NDK]
if "%ANDROID_NDK_HOME%"=="" (
  echo   Status: NOT SET
  echo  .
  echo   Trying to auto-detect...

  REM Try common locations
  set "NDK_FOUND=""

  REM Check LOCALAPPDATA
  if exist "%LOCALAPPDATA%\Android\Sdk\ndk" (
    for /d %%d in ("%LOCALAPPDATA%\Android\Sdk\ndk\*") do (
      if exist "%%d\build\cmake\android.toolchain.cmake" (
        echo   Found: %%d
        set "NDK_FOUND=%%d"
      )
    )
  )

  REM Check user profile
  if not defined NDK_FOUND (
    if exist "%USERPROFILE%\Android\Sdk\ndk" (
      for /d %%d in ("%USERPROFILE%\Android\Sdk\ndk\*") do (
        if exist "%%d\build\cmake\android.toolchain.cmake" (
          echo   Found: %%d
          set "NDK_FOUND=%%d"
        )
      )
    )
  )

  if defined NDK_FOUND (
    echo.
    echo   Set ANDROID_NDK_HOME to use this NDK:
    echo   set ANDROID_NDK_HOME=!NDK_FOUND!
  ) else (
    echo   No NDK found automatically.
    echo   Please install NDK via Android Studio SDK Manager.
  )
) else (
  if exist "%ANDROID_NDK_HOME%" (
    echo   Status: OK
    echo   Path: %ANDROID_NDK_HOME%

    REM Check toolchain
    if exist "%ANDROID_NDK_HOME%\build\cmake\android.toolchain.cmake" (
      echo   Toolchain: OK
    ) else (
      echo   Toolchain: MISSING
    )

    REM Check version
    if exist "%ANDROID_NDK_HOME%\source.properties" (
      for /f "tokens=2 delims==" %%v in ('findstr "Pkg.Revision" "%ANDROID_NDK_HOME%\source.properties"') do (
        echo   Version: %%v
      )
    )
  ) else (
    echo   Status: PATH NOT FOUND
    echo   Path: %ANDROID_NDK_HOME%
  )
)

echo.

REM Check for HarmonyOS NDK
echo [HarmonyOS NDK]
if "%OHOS_NDK_HOME%"=="" (
  echo   Status: NOT SET
  echo   Set OHOS_NDK_HOME for HarmonyOS builds.
) else (
  if exist "%OHOS_NDK_HOME%" (
    echo   Status: OK
    echo   Path: %OHOS_NDK_HOME%
  ) else (
    echo   Status: PATH NOT FOUND
  )
)

echo.

REM Check build tools
echo [Build Tools]"
where cmake >nul 2>&1
if errorlevel 1 (
  echo   cmake: NOT FOUND
) else (
  for /f "tokens=*" %%v in ('cmake --version 2^>^&1 ^| findstr "cmake version"') do echo   %%v
)

where ninja >nul 2>&1
if errorlevel 1 (
  echo   ninja: NOT FOUND ^(will use NDK's ninja if available^)
) else (
  for /f "tokens=*" %%v in ('ninja --version 2^>^&1') do echo   ninja: %%v
)

echo.

REM Check third_party dependencies
echo [Third-party Dependencies]
set "SCRIPT_DIR=%~dp0"
set "PROJECT_ROOT=%SCRIPT_DIR%.."

for %%d in (CLI11 spdlog nlohmann_json cpp_httplib websocketpp asio linenoise-ng openssl) do (
  if exist "%PROJECT_ROOT%\third_party\%%d" (
    echo   %%d: OK
  ) else (
    echo   %%d: MISSING
  )
)

echo.
echo ============================================
echo Check Complete
echo ============================================
