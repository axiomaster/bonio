# Build script for Android
# Usage: ./build_android.ps1 [Release|Debug]

param(
    [string]$BuildType = "Release"
)

$ErrorActionPreference = "Stop"

Write-Host "Building phone-use-agent for Android..." -ForegroundColor Green

$BuildDir = "build/android"

# Check for Android NDK
$AndroidNdk = $env:ANDROID_NDK_HOME
if (-not $AndroidNdk) {
    $AndroidNdk = $env:ANDROID_NDK
}
if (-not $AndroidNdk) {
    $LocalSdk = "C:\Users\$env:USERNAME\AppData\Local\Android\Sdk\ndk"
    if (Test-Path $LocalSdk) {
        $NdkVersions = Get-ChildItem $LocalSdk | Sort-Object -Descending
        if ($NdkVersions.Count -gt 0) {
            $AndroidNdk = $NdkVersions[0].FullName
        }
    }
}

if (-not $AndroidNdk) {
    Write-Host "Error: Android NDK not found!" -ForegroundColor Red
    Write-Host "Please set ANDROID_NDK_HOME or ANDROID_NDK environment variable" -ForegroundColor Yellow
    exit 1
}

Write-Host "Using Android NDK: $AndroidNdk" -ForegroundColor Cyan

# Create build directory
if (-not (Test-Path $BuildDir)) {
    New-Item -ItemType Directory -Path $BuildDir | Out-Null
}

# Android NDK CMake toolchain
$NdkToolchain = Join-Path $AndroidNdk "build\cmake\android.toolchain.cmake"

# Configure
Write-Host "Configuring..." -ForegroundColor Yellow
cmake -B $BuildDir `
    -DCMAKE_BUILD_TYPE=$BuildType `
    -DCMAKE_TOOLCHAIN_FILE=$NdkToolchain `
    -DANDROID_ABI=arm64-v8a `
    -DANDROID_PLATFORM=android-24 `
    -DANDROID_STL=c++_static `
    -DBUILD_HARMONYOS=OFF `
    -DBUILD_ANDROID=ON

if ($LASTEXITCODE -ne 0) {
    Write-Host "Configuration failed!" -ForegroundColor Red
    exit 1
}

# Build
Write-Host "Building..." -ForegroundColor Yellow
cmake --build $BuildDir --config $BuildType

if ($LASTEXITCODE -ne 0) {
    Write-Host "Build failed!" -ForegroundColor Red
    exit 1
}

Write-Host "Build successful!" -ForegroundColor Green
Write-Host "Output: $BuildDir/bin/phone-use-agent" -ForegroundColor Cyan
