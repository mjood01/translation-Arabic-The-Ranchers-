param([Parameter(Mandatory=$true)][string]$BackupPath)
$ErrorActionPreference = 'Stop'
$BackupPath = [System.IO.Path]::GetFullPath($BackupPath)
$dataPath = Split-Path -Parent $BackupPath
if ((Split-Path -Leaf $dataPath) -ne 'TheRanchers_Data' -or (Split-Path -Leaf $BackupPath) -notlike 'arabic-backup-*') { throw 'Select a backup created by this installer.' }
if (Get-Process -Name TheRanchers,AssetRipper -ErrorAction SilentlyContinue) { throw 'Close the game and AssetRipper first.' }
$manifest = Get-Content -LiteralPath (Join-Path $BackupPath 'installed-release.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$pending = @()
foreach ($entry in $manifest.files) {
    if ($entry.name -notin @('level2','level6','sharedassets0.assets','resources.assets')) { throw 'Unexpected backup entry.' }
    $saved = Join-Path $BackupPath $entry.name
    if (-not (Test-Path -LiteralPath $saved)) { continue }
    $live = Join-Path $dataPath $entry.name
    if ((Get-FileHash -LiteralPath $saved -Algorithm SHA256).Hash -ne $entry.source_sha256 -or
        (Get-FileHash -LiteralPath $live -Algorithm SHA256).Hash -ne $entry.target_sha256) { throw 'A game or backup file differs. Restore stopped.' }
    if (Test-Path -LiteralPath ($saved + '.arabic')) { throw 'Restoration archive already exists.' }
    $pending += $entry
}
$done = @()
try {
    foreach ($entry in $pending) {
        $live = Join-Path $dataPath $entry.name
        $saved = Join-Path $BackupPath $entry.name
        [System.IO.File]::Move($live, $saved + '.arabic')
        $done += $entry.name
        [System.IO.File]::Move($saved, $live)
    }
} catch {
    foreach ($name in $done) {
        $live = Join-Path $dataPath $name
        $saved = Join-Path $BackupPath $name
        if (Test-Path -LiteralPath $live) { [System.IO.File]::Move($live, $saved) }
        [System.IO.File]::Move($saved + '.arabic', $live)
    }
    throw
}
Write-Output 'Original files restored. The Arabic files remain in the backup directory with the .arabic suffix.'
