# Bundle hiclaw.exe into the Windows build output.
# Usage: scripts/bundle-hiclaw.ps1 [-BuildDir <path>]
param(
  [string]$BuildDir = ""
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Resolve-Path "$ScriptDir\..\.."
$HiclawBin = "$ProjectRoot\server\bin\hiclaw.exe"

if (-not (Test-Path $HiclawBin)) {
  Write-Error "hiclaw.exe not found at $HiclawBin. Build the server first."
  exit 1
}

if ($BuildDir -eq "") {
  # Try Ninja output path first (no config subdir), then VS path
  $NinjaDir = "$ProjectRoot\desktop\build\windows\x64\runner"
  $VsDir = "$ProjectRoot\desktop\build\windows\x64\runner\Release"
  if (Test-Path "$NinjaDir\bonio_desktop.exe") {
    $BuildDir = $NinjaDir
  } elseif (Test-Path "$VsDir\bonio_desktop.exe") {
    $BuildDir = $VsDir
  } elseif (Test-Path $VsDir) {
    $BuildDir = $VsDir
  } elseif (Test-Path $NinjaDir) {
    $BuildDir = $NinjaDir
  } else {
    Write-Error "Build directory not found. Tried: $NinjaDir, $VsDir"
    exit 1
  }
}

Copy-Item $HiclawBin "$BuildDir\hiclaw.exe" -Force
Write-Host "Bundled hiclaw.exe -> $BuildDir\hiclaw.exe"
