# Build script for HarmonyOS
# Usage: ./build_harmonyos.ps1 [Release|Debug]

param(
    [string]$BuildType = "Release"
)

$ErrorActionPreference = "Stop"

Write-Host "Building phone-use-agent for HarmonyOS..." -ForegroundColor Green

$BuildDir = "build/harmonyos"
$OHOS_NDK = "D:/tools/commandline-tools-windows/sdk/default/openharmony/native"
$NinjaPath = "${OHOS_NDK}/build-tools/cmake/bin/ninja.exe"
$ToolchainFile = "$(Get-Location)/cmake/HarmonyOS-toolchain.cmake"

# Create build directory
if (-not (Test-Path $BuildDir)) {
    New-Item -ItemType Directory -Path $BuildDir | Out-Null
}

# Configure
Write-Host "Configuring..." -ForegroundColor Yellow
cmake -B $BuildDir -G Ninja `
    "-DCMAKE_BUILD_TYPE=$BuildType" `
    "-DCMAKE_MAKE_PROGRAM=$NinjaPath" `
    "-DCMAKE_TOOLCHAIN_FILE=$ToolchainFile" `
    -DBUILD_HARMONYOS=ON `
    -DBUILD_ANDROID=OFF

if ($LASTEXITCODE -ne 0) {
    Write-Host "Configuration failed!" -ForegroundColor Red
    exit 1
}

# Build
Write-Host "Building..." -ForegroundColor Yellow
& $NinjaPath -C $BuildDir

if ($LASTEXITCODE -ne 0) {
    Write-Host "Build failed!" -ForegroundColor Red
    exit 1
}

Write-Host "Build successful!" -ForegroundColor Green
Write-Host "Output: $BuildDir/bin/phone-use-agent" -ForegroundColor Cyan
