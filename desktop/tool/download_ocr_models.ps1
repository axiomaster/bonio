# Download PP-OCRv4 ONNX models for local OCR.
# Requires: curl or Invoke-WebRequest
# Output: desktop/assets/ocr/{det.onnx, rec.onnx, dict.txt}

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Resolve-Path "$ScriptDir\.."
$OutDir = "$ProjectRoot\assets\ocr"

if (-not (Test-Path $OutDir)) {
  New-Item -ItemType Directory -Path $OutDir | Out-Null
}

Write-Host "Downloading PP-OCRv4 ONNX models to $OutDir" -ForegroundColor Cyan

# Source: PaddleOCR ONNX exports (community-maintained, ~10MB total)
$BaseUrl = "https://github.com/RapidAI/RapidOCR/releases/download/v1.1.0"

$Files = @(
  @{Name="det.onnx"; Url="$BaseUrl/ch_PP-OCRv4_det_infer.onnx"},
  @{Name="rec.onnx"; Url="$BaseUrl/ch_PP-OCRv4_rec_infer.onnx"},
  @{Name="dict.txt"; Url="$BaseUrl/ppocr_keys_v1.txt"}
)

foreach ($f in $Files) {
  $out = "$OutDir\$($f.Name)"
  if (Test-Path $out) {
    Write-Host "  SKIP $($f.Name) (already exists)" -ForegroundColor Gray
    continue
  }
  Write-Host "  Downloading $($f.Name)..." -ForegroundColor Gray
  try {
    curl -L -o "$out" $f.Url 2>$null
    if ($LASTEXITCODE -ne 0) {
      Invoke-WebRequest -Uri $f.Url -OutFile $out
    }
    Write-Host "    OK ($((Get-Item $out).Length) bytes)" -ForegroundColor Green
  } catch {
    Write-Host "    FAILED: $_" -ForegroundColor Red
    Write-Host "    Please download models manually from:"
    Write-Host "      https://github.com/RapidAI/RapidOCR"
    exit 1
  }
}

Write-Host "Done. Models in: $OutDir" -ForegroundColor Green
Write-Host "  det.onnx  — PP-OCRv4 detection model"
Write-Host "  rec.onnx  — PP-OCRv4 recognition model"
Write-Host "  dict.txt  — character dictionary"
