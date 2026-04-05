# Downloads the Sherpa-ONNX streaming paraformer bilingual zh-en model
# (same model used by the Android app).
#
# Usage:
#   cd desktop
#   powershell -ExecutionPolicy Bypass -File tool/download_model.ps1
#
# The model is extracted next to the built executable so that the app
# can find it at runtime.  For debug builds the default path is:
#   build/windows/x64/runner/Debug/sherpa-onnx-streaming-paraformer-bilingual-zh-en/

param(
    [string]$TargetDir = ""
)

$ErrorActionPreference = "Stop"

$ModelName = "sherpa-onnx-streaming-paraformer-bilingual-zh-en"
$Url = "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/$ModelName.tar.bz2"
$Archive = "$ModelName.tar.bz2"

if (-not $TargetDir) {
    $TargetDir = Join-Path (Join-Path (Join-Path (Join-Path (Join-Path (Join-Path $PSScriptRoot "..") "build") "windows") "x64") "runner") "Debug"
}

$DestDir = Join-Path $TargetDir $ModelName

if (Test-Path (Join-Path $DestDir "encoder.int8.onnx")) {
    Write-Host "Model already exists at $DestDir — skipping download."
    exit 0
}

Write-Host "Downloading $ModelName ..."
Write-Host "URL: $Url"

$TempDir = Join-Path $env:TEMP "sherpa_model_download"
New-Item -ItemType Directory -Force -Path $TempDir | Out-Null
$ArchivePath = Join-Path $TempDir $Archive

if (-not (Test-Path $ArchivePath)) {
    Invoke-WebRequest -Uri $Url -OutFile $ArchivePath -UseBasicParsing
    Write-Host "Downloaded to $ArchivePath"
} else {
    Write-Host "Archive already cached at $ArchivePath"
}

Write-Host "Extracting ..."
New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null

# tar can handle .tar.bz2 on Windows 10+
tar -xjf $ArchivePath -C $TargetDir

if (Test-Path (Join-Path $DestDir "encoder.int8.onnx")) {
    Write-Host "Model extracted to $DestDir"
    Write-Host "Files:"
    Get-ChildItem $DestDir | ForEach-Object {
        $sizeMB = [math]::Round($_.Length / 1MB, 1)
        Write-Host "  $($_.Name)  ($sizeMB MB)"
    }
} else {
    Write-Error "Extraction failed — encoder.int8.onnx not found in $DestDir"
    exit 1
}

Write-Host ""
Write-Host "Done. You can now run:  flutter run -d windows"
