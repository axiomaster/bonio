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
  $BuildDir = "$ProjectRoot\desktop\build\windows\x64\runner\Release"
}

if (-not (Test-Path $BuildDir)) {
  Write-Error "Build directory not found: $BuildDir"
  exit 1
}

Copy-Item $HiclawBin "$BuildDir\hiclaw.exe" -Force
Write-Host "Bundled hiclaw.exe -> $BuildDir\hiclaw.exe"
