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

# Bundle PaddleOCR native DLL + ONNX models
$PaddleOcrDll = "$ProjectRoot\desktop\lib\platform\ocr\native\build\paddle_ocr_plugin.dll"
if (Test-Path $PaddleOcrDll) {
  Copy-Item $PaddleOcrDll "$BuildDir\paddle_ocr_plugin.dll" -Force
  Write-Host "Bundled paddle_ocr_plugin.dll -> $BuildDir\paddle_ocr_plugin.dll"
} else {
  Write-Host "SKIP paddle_ocr_plugin.dll (not built — run desktop/lib/platform/ocr/native/build.bat)"
}

# Copy OCR models
$OcrModelsDir = "$ProjectRoot\assets\ocr"
$OcrDest = "$BuildDir\assets\ocr"
if (Test-Path $OcrModelsDir) {
  if (-not (Test-Path $OcrDest)) { New-Item -ItemType Directory -Path $OcrDest | Out-Null }
  foreach ($f in @("det.onnx", "rec.onnx", "dict.txt")) {
    $src = "$OcrModelsDir\$f"
    if (Test-Path $src) {
      Copy-Item $src "$OcrDest\$f" -Force
      Write-Host "Bundled $f -> $OcrDest\$f"
    }
  }
}
