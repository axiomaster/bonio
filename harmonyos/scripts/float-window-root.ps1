param(
    [string]$BundleName = "com.axiomaster.bonio",
    [string]$HdcPath = "",
    [string]$Python = "python",
    [string]$WorkDir = "",
    [switch]$Apply,
    [switch]$NoReboot,
    [switch]$SkipPull
)

$ErrorActionPreference = "Stop"

if ($BundleName -ne "com.axiomaster.bonio") {
    throw "Refusing to patch non-default bundle '$BundleName'. Edit the script if this is intentional."
}

$harmonyosRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = Split-Path -Parent $harmonyosRoot
$patcher = Join-Path $PSScriptRoot "float_window_patch.py"
if (-not (Test-Path $patcher)) {
    throw "Missing patcher: $patcher"
}

if ([string]::IsNullOrWhiteSpace($HdcPath)) {
    if ($env:DEVECO_SDK_HOME) {
        $candidate = Join-Path $env:DEVECO_SDK_HOME "default\openharmony\toolchains\hdc.exe"
        if (Test-Path $candidate) {
            $HdcPath = $candidate
        }
    }
}
if ([string]::IsNullOrWhiteSpace($HdcPath)) {
    $cmd = Get-Command hdc -ErrorAction SilentlyContinue
    if ($cmd) {
        $HdcPath = $cmd.Source
    }
}
if ([string]::IsNullOrWhiteSpace($HdcPath) -or -not (Test-Path $HdcPath)) {
    throw "Could not locate hdc. Set -HdcPath or DEVECO_SDK_HOME."
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
if ([string]::IsNullOrWhiteSpace($WorkDir)) {
    $WorkDir = Join-Path $repoRoot ".codex-build\harmonyos-float-window\$timestamp"
}
$originalDir = Join-Path $WorkDir "original"
$patchedDir = Join-Path $WorkDir "patched"
New-Item -ItemType Directory -Force $originalDir | Out-Null
New-Item -ItemType Directory -Force $patchedDir | Out-Null

function Invoke-Hdc {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
    & $HdcPath @Args
    if ($LASTEXITCODE -ne 0) {
        throw "hdc failed: $($Args -join ' ')"
    }
}

function Invoke-HdcShell {
    param([string]$Command)
    Invoke-Hdc shell $Command
}

Write-Host "Using hdc: $HdcPath"
Write-Host "Work dir: $WorkDir"
Write-Host "Mode: $($(if ($Apply) { 'APPLY' } else { 'DRY-RUN' }))"

$targets = & $HdcPath list targets
if ($LASTEXITCODE -ne 0 -or -not ($targets -match "\S")) {
    throw "No HarmonyOS target found via hdc."
}
Write-Host "Targets:"
Write-Host $targets

$idOutput = & $HdcPath shell "id"
if ($LASTEXITCODE -ne 0) {
    throw "Failed to run 'id' through hdc."
}
Write-Host $idOutput
if (-not ($idOutput -match "uid=0\(root\)")) {
    throw "Device shell is not root. This script requires an already-rooted device."
}

$remoteBmsDir = "/data/service/el1/public/bms/bundle_manager_service"
$remoteAccessDir = "/data/service/el1/public/access_token"
$remoteTmp = "/data/local/tmp/bonio_float_window_patch_$timestamp"

if (-not $SkipPull) {
    Write-Host "Pulling system databases..."
    Invoke-Hdc file recv "$remoteBmsDir/bmsdb.db" (Join-Path $originalDir "bmsdb.db")
    Invoke-Hdc file recv "$remoteBmsDir/bmsdb_slave.db" (Join-Path $originalDir "bmsdb_slave.db")
    Invoke-Hdc file recv "$remoteAccessDir/access_token.db" (Join-Path $originalDir "access_token.db")
    Invoke-Hdc file recv "$remoteAccessDir/access_token_slave.db" (Join-Path $originalDir "access_token_slave.db")
}

$required = @(
    "bmsdb.db",
    "bmsdb_slave.db",
    "access_token.db",
    "access_token_slave.db"
)
foreach ($name in $required) {
    $path = Join-Path $originalDir $name
    if (-not (Test-Path $path)) {
        throw "Missing local input DB: $path"
    }
}

Write-Host "Patching local database copies..."
& $Python $patcher `
    --bundle $BundleName `
    --bms-db (Join-Path $originalDir "bmsdb.db") `
    --bms-slave-db (Join-Path $originalDir "bmsdb_slave.db") `
    --access-db (Join-Path $originalDir "access_token.db") `
    --access-slave-db (Join-Path $originalDir "access_token_slave.db") `
    --out-dir $patchedDir | Tee-Object -FilePath (Join-Path $WorkDir "patch-summary.json")
if ($LASTEXITCODE -ne 0) {
    throw "Local patch failed."
}

if (-not $Apply) {
    Write-Host ""
    Write-Host "Dry-run complete. Patched files are in:"
    Write-Host $patchedDir
    Write-Host "Re-run with -Apply to write them to the connected root device."
    exit 0
}

Write-Host "Sending patched databases to device temp dir..."
Invoke-HdcShell "rm -rf $remoteTmp; mkdir -p $remoteTmp"
Invoke-Hdc file send (Join-Path $patchedDir "bmsdb.db") "$remoteTmp/bmsdb.db"
Invoke-Hdc file send (Join-Path $patchedDir "bmsdb_slave.db") "$remoteTmp/bmsdb_slave.db"
Invoke-Hdc file send (Join-Path $patchedDir "access_token.db") "$remoteTmp/access_token.db"
Invoke-Hdc file send (Join-Path $patchedDir "access_token_slave.db") "$remoteTmp/access_token_slave.db"

Write-Host "Writing BMS databases with backups..."
$bmsWrite = @"
set -e
base=$remoteBmsDir
patch=$remoteTmp
cd `$base
cp bmsdb.db bmsdb.db.before_bonio_float_patch_$timestamp
cp bmsdb_slave.db bmsdb_slave.db.before_bonio_float_patch_$timestamp
mv bmsdb.db bmsdb.db.old_bonio_float_patch_$timestamp
mv bmsdb_slave.db bmsdb_slave.db.old_bonio_float_patch_$timestamp
cp `$patch/bmsdb.db bmsdb.db
cp `$patch/bmsdb_slave.db bmsdb_slave.db
chown foundation:foundation bmsdb.db bmsdb_slave.db
chmod 0660 bmsdb.db bmsdb_slave.db
chcon u:object_r:bms_db_file:s0 bmsdb.db bmsdb_slave.db
ls -lZ bmsdb.db bmsdb_slave.db
sync
"@
Invoke-HdcShell $bmsWrite

Write-Host "Writing AccessToken databases with backups..."
$accessWrite = @"
set -e
base=$remoteAccessDir
patch=$remoteTmp
cd `$base
cp access_token.db access_token.db.before_bonio_float_patch_$timestamp
cp access_token_slave.db access_token_slave.db.before_bonio_float_patch_$timestamp
rm -f access_token.db-wal access_token.db-shm access_token.db-dwr
rm -f access_token_slave.db-wal access_token_slave.db-shm access_token_slave.db-dwr
mv access_token.db access_token.db.old_bonio_float_patch_$timestamp
mv access_token_slave.db access_token_slave.db.old_bonio_float_patch_$timestamp
cp `$patch/access_token.db access_token.db
cp `$patch/access_token_slave.db access_token_slave.db
chown access_token:access_token access_token.db access_token_slave.db
chmod 0660 access_token.db access_token_slave.db
chcon u:object_r:accesstoken_data_file:s0 access_token.db access_token_slave.db
ls -lZ access_token.db access_token_slave.db
sync
"@
Invoke-HdcShell $accessWrite

if ($NoReboot) {
    Write-Host "Apply complete. -NoReboot was set; reboot manually before final verification."
    exit 0
}

Write-Host "Rebooting device so BMS and AccessToken reload patched DBs..."
& $HdcPath shell "sync; reboot" | Out-Null
Write-Host "Patch applied. After the device comes back, verify with:"
Write-Host "  bm dump -n $BundleName | grep SYSTEM_FLOAT_WINDOW -C 3"
Write-Host "Then start Bonio and enable the Cat Overlay switch."
