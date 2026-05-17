# Bonio Windows Release Script
# Usage: scripts\release-windows.ps1 [-Version <semver>]
# Example: scripts\release-windows.ps1 -Version 0.1.0
param(
    [string]$Version = ""
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Resolve-Path "$ScriptDir\.."
$ServerDir = "$ProjectRoot\server"
$DesktopDir = "$ProjectRoot\desktop"

# Read version from pubspec.yaml if not specified
if ($Version -eq "") {
    $pubspec = Get-Content "$DesktopDir\pubspec.yaml" -Raw
    if ($pubspec -match 'version:\s*(\d+\.\d+\.\d+)') {
        $Version = $Matches[1]
    } else {
        Write-Error "Cannot determine version from pubspec.yaml"
        exit 1
    }
}

Write-Host "============================================" -ForegroundColor Cyan
Write-Host " Bonio v$Version Windows Release" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# ---------- Step 1: Build hiclaw server ----------
Write-Host "[1/4] Building hiclaw server..." -ForegroundColor Yellow
& "$ServerDir\scripts\build-win-amd64.bat"
if ($LASTEXITCODE -ne 0) {
    Write-Error "hiclaw build failed"
    exit 1
}

# ---------- Step 2: Build Flutter desktop ----------
Write-Host ""
Write-Host "[2/4] Building Flutter desktop..." -ForegroundColor Yellow

Push-Location $DesktopDir
try {
    # Ensure MSVC toolchain
    $vcvarsPaths = @(
        "C:\Program Files\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat",
        "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat",
        "C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvars64.bat",
        "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat",
        "C:\Program Files (x86)\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
    )
    foreach ($p in $vcvarsPaths) {
        if (Test-Path $p) {
            Write-Host "  Setting up MSVC from $p"
            cmd /c "`"$p`" >nul 2>&1 && set" | ForEach-Object {
                if ($_ -match '^([^=]+)=(.*)$') {
                    [System.Environment]::SetEnvironmentVariable($Matches[1], $Matches[2], 'Process')
                }
            }
            break
        }
    }

    # Use Ninja for cleaner build
    $env:PATH = "$DesktopDir\scripts;$env:PATH"

    & flutter pub get
    if ($LASTEXITCODE -ne 0) { Write-Error "flutter pub get failed"; exit 1 }

    & flutter build windows --no-pub
    if ($LASTEXITCODE -ne 0) { Write-Error "Flutter build failed"; exit 1 }

    # Ninja install step
    cmake --install "$DesktopDir\build\windows\x64" --config Release 2>$null
} finally {
    Pop-Location
}

# ---------- Step 3: Bundle ----------
Write-Host ""
Write-Host "[3/4] Bundling hiclaw + assets..." -ForegroundColor Yellow
& powershell -ExecutionPolicy Bypass -File "$DesktopDir\scripts\bundle-hiclaw.ps1"
if ($LASTEXITCODE -ne 0) {
    Write-Error "Bundle failed"
    exit 1
}

# ---------- Step 4: Package ----------
Write-Host ""
Write-Host "[4/4] Packaging release..." -ForegroundColor Yellow

# Find build output
$BuildDir = $null
$NinjaDir = "$DesktopDir\build\windows\x64\runner"
$VsDir = "$DesktopDir\build\windows\x64\runner\Release"
if (Test-Path "$NinjaDir\bonio_desktop.exe") {
    $BuildDir = $NinjaDir
} elseif (Test-Path "$VsDir\bonio_desktop.exe") {
    $BuildDir = $VsDir
} else {
    Write-Error "Build output not found"
    exit 1
}
Write-Host "  Build dir: $BuildDir"

# Create release directory
$ReleaseDir = "$ProjectRoot\release\v$Version"
if (Test-Path $ReleaseDir) { Remove-Item $ReleaseDir -Recurse -Force }
New-Item -ItemType Directory -Path $ReleaseDir -Force | Out-Null

# Create ZIP using .NET (no 7-Zip needed)
$ZipName = "Bonio-v$Version-windows-x64.zip"
$ZipPath = "$ReleaseDir\$ZipName"
Write-Host "  Creating $ZipName..."

# Temp staging directory
$StageDir = "$ReleaseDir\Bonio"
if (Test-Path $StageDir) { Remove-Item $StageDir -Recurse -Force }
New-Item -ItemType Directory -Path $StageDir -Force | Out-Null

# Copy build output to staging
Get-ChildItem $BuildDir | Copy-Item -Destination $StageDir -Recurse -Force

# Copy STT model files if they exist
$ModelDir = "$DesktopDir\tool\model"
if (Test-Path $ModelDir) {
    $DestModel = "$StageDir\model"
    New-Item -ItemType Directory -Path $DestModel -Force | Out-Null
    Get-ChildItem $ModelDir -File | Copy-Item -Destination $DestModel -Force
    Write-Host "  Bundled STT model files"
}

# Compress to ZIP
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($StageDir, $ZipPath)
Remove-Item $StageDir -Recurse -Force

$ZipSize = [math]::Round((Get-Item $ZipPath).Length / 1MB, 1)
Write-Host "  Created: $ZipPath ($ZipSize MB)"

# ---------- Generate RELEASE-NOTES.md ----------
$date = Get-Date -Format 'yyyy-MM-dd'
$gitLog = git -C $ProjectRoot log --oneline --no-merges -20 | ForEach-Object { "- $_" }
$gitLogText = $gitLog -join "`n"

$ReleaseNotes = @"
# Bonio v$Version - Windows Release

**Release Date:** $date
**Platform:** Windows x64
**Package:** ``$ZipName``

## System Requirements

- Windows 10 / 11 (x64)
- No additional runtime required

## Features

### AI Companion
- Floating cat avatar on your window edge with rich emotions
- Voice input with local offline STT (Sherpa-ONNX paraformer)
- TTS responses via PowerShell System.Speech

### Memory System
- One-click screenshot capture with AI auto-tagging and summarization
- Drag-and-drop text/images/files onto the avatar
- Conversational retrieval of stored memories

### Note Export and Sync
- Export notes to Obsidian (Markdown + YAML frontmatter + Wiki links)
- ZIP archive export for backup and migration
- Auto-sync: new notes automatically exported to Obsidian
- Batch export with progress tracking

### Reading Companion
- Browser article reading with 70/30 split screen
- AI-powered table of contents and summarization

### Plugin System
- Dynamic plugin loading (any language)
- Right-click context menu extensions

### Multi-platform
- Desktop (Windows / macOS) + Mobile (Android / HarmonyOS)
- WeChat integration for remote desktop control

## Installation

1. Extract ZIP file
2. Run bonio_desktop.exe
3. Server tab - enter gateway address

## Known Issues

- First launch may trigger Windows SmartScreen warning (unsigned binary)
- STT model files need separate download for voice input

## What's New

$gitLogText
"@

$ReleaseNotesPath = "$ReleaseDir\RELEASE-NOTES.md"
[System.IO.File]::WriteAllText($ReleaseNotesPath, $ReleaseNotes, [System.Text.Encoding]::UTF8)
Write-Host "  Generated RELEASE-NOTES.md"

# ---------- Done ----------
Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host " Release v$Version complete!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Output directory: $ReleaseDir"
Get-ChildItem $ReleaseDir | ForEach-Object {
    $size = if ($_.PSIsContainer) { "" } else { " ($([math]::Round($_.Length / 1MB, 1)) MB)" }
    Write-Host "    $($_.Name)$size"
}
