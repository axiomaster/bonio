# cmake-wrapper.ps1
# Intercepts cmake calls from Flutter, replaces Visual Studio generator with Ninja.
# This allows building Flutter Windows apps without Visual Studio.
#
# Usage: Set CMAKE_WRAPPER=1 before running flutter build, or use build-desktop.bat --ninja

param([string[]]$Arguments)

# Find the real cmake (skip ourselves)
$realCmake = (Get-Command cmake -ErrorAction SilentlyContinue | Where-Object { $_.Source -notmatch 'cmake-wrapper' } | Select-Object -First 1).Source
if (-not $realCmake) {
    # Fallback: search PATH excluding this script's directory
    $wrapperDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $paths = $env:PATH -split ';' | Where-Object { $_ -ne $wrapperDir -and $_ -ne "$wrapperDir\" }
    $realCmake = $paths | ForEach-Object { Get-Command "$_\cmake.exe" -ErrorAction SilentlyContinue } | Select-Object -First 1 | ForEach-Object { $_.Source }
}
if (-not $realCmake) {
    Write-Error "cmake.exe not found in PATH (excluding this wrapper)"
    exit 1
}

# Replace Visual Studio generator with Ninja
$newArgs = @()
$skipNext = $false
for ($i = 0; $i -lt $Arguments.Count; $i++) {
    if ($skipNext) {
        $skipNext = $false
        continue
    }
    if ($Arguments[$i] -eq '-G') {
        $generator = $Arguments[$i + 1]
        if ($generator -match 'Visual Studio') {
            Write-Host "[cmake-wrapper] Replacing generator '$generator' with 'Ninja'" -ForegroundColor Cyan
            $newArgs += '-G'
            $newArgs += 'Ninja'
            $skipNext = $true
            continue
        }
    }
    $newArgs += $Arguments[$i]
}

# When using Ninja (single-config), ensure CMAKE_BUILD_TYPE is set
# The Flutter tool passes -A x64 which is not valid for Ninja, so drop -A and its arg
$filteredArgs = @()
$skipNext = $false
$hasBuildType = $false
for ($i = 0; $i -lt $newArgs.Count; $i++) {
    if ($skipNext) {
        $skipNext = $false
        continue
    }
    if ($newArgs[$i] -eq '-A') {
        $skipNext = $true
        continue
    }
    if ($newArgs[$i] -eq '-DCMAKE_BUILD_TYPE') {
        $hasBuildType = $true
    }
    $filteredArgs += $newArgs[$i]
}

# Ninja is single-config; ensure CMAKE_BUILD_TYPE=Release so the build is optimized
# (VS generator handles this via --config Release at build time)
if (-not $hasBuildType) {
    $filteredArgs += '-DCMAKE_BUILD_TYPE=Release'
    Write-Host "[cmake-wrapper] Added -DCMAKE_BUILD_TYPE=Release for Ninja single-config build" -ForegroundColor DarkGray
}

Write-Host "[cmake-wrapper] Running: cmake $($filteredArgs -join ' ')" -ForegroundColor DarkGray

# Run the real cmake
& $realCmake @filteredArgs
exit $LASTEXITCODE
