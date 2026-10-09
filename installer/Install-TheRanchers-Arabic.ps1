param([string]$GameDataPath)
$ErrorActionPreference = 'Stop'
if (-not $GameDataPath) {
    Add-Type -AssemblyName System.Windows.Forms
    $picker = New-Object System.Windows.Forms.FolderBrowserDialog
    $picker.Description = 'Select TheRanchers_Data inside your The Ranchers installation.'
    if ($picker.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { exit 0 }
    $GameDataPath = $picker.SelectedPath
    $picker.Dispose()
}
$GameDataPath = [System.IO.Path]::GetFullPath($GameDataPath)
if ((Split-Path -Leaf $GameDataPath) -ne 'TheRanchers_Data') { throw 'Select the TheRanchers_Data directory.' }
if (Get-Process -Name TheRanchers,AssetRipper -ErrorAction SilentlyContinue) { throw 'Close The Ranchers and AssetRipper first.' }
$manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($manifest.format -ne 1) { throw 'Unsupported package format.' }
$allowed = @('level2','level6','sharedassets0.assets','resources.assets')
if ($manifest.files.Count -ne 4) { throw 'Incomplete package.' }
$pending = @()
foreach ($entry in $manifest.files) {
    if ($entry.name -notin $allowed -or $entry.payload -ne ($entry.name + '.patchdata')) { throw 'Unexpected package file.' }
    $live = Join-Path $GameDataPath $entry.name
    if (-not (Test-Path -LiteralPath $live -PathType Leaf)) { throw "Missing game file: $($entry.name)" }
    $hash = (Get-FileHash -LiteralPath $live -Algorithm SHA256).Hash
    if ($hash -eq $entry.target_sha256 -and (Get-Item -LiteralPath $live).Length -eq $entry.target_size) { continue }
    if ($hash -ne $entry.source_sha256 -or (Get-Item -LiteralPath $live).Length -ne $entry.source_size) {
        throw "Unsupported or modified game file: $($entry.name). Restore the original version 0.8.10.872 through Steam before installing. No files have been changed."
    }
    $payload = Join-Path $PSScriptRoot $entry.payload
    $recipe = Join-Path $PSScriptRoot ($entry.name + '.recipe.json')
    if ((Get-FileHash -LiteralPath $payload -Algorithm SHA256).Hash -ne $entry.payload_sha256 -or
        (Get-FileHash -LiteralPath $recipe -Algorithm SHA256).Hash -ne $entry.recipe_sha256) { throw 'Package integrity check failed.' }
    $pending += $entry
}
if ($pending.Count -eq 0) { Write-Output 'This Arabic release is already installed.'; exit 0 }
Add-Type -Path (Join-Path $PSScriptRoot 'Apply-AssetRecipe.cs') -ReferencedAssemblies @('System.Web.Extensions','System.IO.Compression')
$stamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0,8)
$backup = Join-Path $GameDataPath ('arabic-backup-' + $stamp)
$prepared = @(); $installed = @()
try {
    foreach ($entry in $pending) {
        $live = Join-Path $GameDataPath $entry.name
        $stage = Join-Path $GameDataPath ($entry.name + '.arabic-stage-' + $stamp)
        $prepared += $stage
        Write-Output "Preparing $($entry.name)..."
        [RanchersAssetRecipe]::Apply($live, (Join-Path $PSScriptRoot $entry.payload), (Join-Path $PSScriptRoot ($entry.name + '.recipe.json')), $stage, [long]$entry.target_size)
        if ((Get-FileHash -LiteralPath $stage -Algorithm SHA256).Hash -ne $entry.target_sha256) { throw 'Prepared file failed verification.' }
    }
    if (Get-Process -Name TheRanchers,AssetRipper -ErrorAction SilentlyContinue) { throw 'The game was started during preparation. Close it and retry.' }
    foreach ($entry in $pending) {
        if ((Get-FileHash -LiteralPath (Join-Path $GameDataPath $entry.name) -Algorithm SHA256).Hash -ne $entry.source_sha256) { throw 'Source file changed during preparation.' }
    }
    $null = New-Item -ItemType Directory -Path $backup
    foreach ($entry in $pending) {
        $live = Join-Path $GameDataPath $entry.name
        $saved = Join-Path $backup $entry.name
        $stage = Join-Path $GameDataPath ($entry.name + '.arabic-stage-' + $stamp)
        [System.IO.File]::Move($live, $saved)
        $installed += $entry.name
        [System.IO.File]::Move($stage, $live)
    }
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'manifest.json') -Destination (Join-Path $backup 'installed-release.json')
    Write-Output "Installation completed. Backup: $backup"
    Write-Output 'Start the game and select the Korean language position for Arabic.'
} catch {
    foreach ($name in $installed) {
        $live = Join-Path $GameDataPath $name
        $saved = Join-Path $backup $name
        if (Test-Path -LiteralPath $saved) {
            if (Test-Path -LiteralPath $live) { [System.IO.File]::Move($live, $live + '.failed-' + $stamp) }
            [System.IO.File]::Move($saved, $live)
        }
    }
    throw
} finally {
    foreach ($stage in $prepared) {
        if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage }
    }
}
