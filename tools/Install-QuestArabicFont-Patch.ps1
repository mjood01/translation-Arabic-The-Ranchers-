param(
    [string]$GameDataPath = 'D:\SteamLibrary\steamapps\common\TheRanchers\TheRanchers_Data'
)

$ErrorActionPreference = 'Stop'
$assetPath = Join-Path $GameDataPath 'level6'
$fontAssetsPath = Join-Path $GameDataPath 'sharedassets0.assets'

if (-not (Test-Path -LiteralPath $assetPath -PathType Leaf)) {
    throw "لم أجد ملف المشهد: $assetPath"
}
if (-not (Test-Path -LiteralPath $fontAssetsPath -PathType Leaf)) {
    throw "لم أجد ملف الخطوط: $fontAssetsPath"
}
if (Get-Process -Name 'TheRanchers' -ErrorAction SilentlyContinue) {
    throw 'أغلق اللعبة بالكامل ثم أعد تشغيل هذا الملف.'
}

# Offsets are for The Ranchers v0.8.10.872, Unity 2022.3.62f3.
# Each offset points to the 8-byte pathID part of a TMP font PPtr.
$entries = @(
    [pscustomobject]@{ Component = 28582; PathIdOffset = 3370408; OldFont = 1558 }
    [pscustomobject]@{ Component = 28918; PathIdOffset = 3543012; OldFont = 1556 }
    [pscustomobject]@{ Component = 28974; PathIdOffset = 3573128; OldFont = 1560 }
    [pscustomobject]@{ Component = 28990; PathIdOffset = 3581384; OldFont = 1556 }
    [pscustomobject]@{ Component = 28998; PathIdOffset = 3585988; OldFont = 1556 }
    [pscustomobject]@{ Component = 29003; PathIdOffset = 3588564; OldFont = 1556 }
)

$alreadyInstalled = $false
$backupPath = $null
$stream = [System.IO.File]::Open(
    $assetPath,
    [System.IO.FileMode]::Open,
    [System.IO.FileAccess]::ReadWrite,
    [System.IO.FileShare]::None
)
try {
    if ($stream.Length -ne 9140148) {
        throw "حجم level6 لا يطابق النسخة التي فُحصت (المتوقع 9,140,148 بايت؛ الموجود $($stream.Length)). لم أعدّل الملف."
    }

    $bytes = [byte[]]::new([int]$stream.Length)
    $stream.Position = 0
    $readTotal = 0
    while ($readTotal -lt $bytes.Length) {
        $read = $stream.Read($bytes, $readTotal, $bytes.Length - $readTotal)
        if ($read -le 0) { throw 'تعذرت قراءة ملف المشهد كاملًا.' }
        $readTotal += $read
    }

    $pending = @()
    foreach ($entry in $entries) {
        $fileId = [BitConverter]::ToInt32($bytes, [int]($entry.PathIdOffset - 4))
        $fontId = [BitConverter]::ToInt64($bytes, [int]$entry.PathIdOffset)
        if ($fileId -ne 2) {
            throw "مرجع الخط في المكوّن $($entry.Component) غير متوقع. لم أعدّل الملف."
        }
        if ($fontId -eq 1553) { continue }
        if ($fontId -ne $entry.OldFont) {
            throw "معرّف الخط في المكوّن $($entry.Component) هو $fontId بدلًا من $($entry.OldFont). لم أعدّل الملف."
        }
        $pending += $entry
    }

    if ($pending.Count -eq 0) {
        $alreadyInstalled = $true
    }
    else {
        $backupPath = Join-Path $GameDataPath ("level6.backup-before-quest-font-{0}.bak" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
        $backupStream = [System.IO.File]::Open(
            $backupPath,
            [System.IO.FileMode]::CreateNew,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::None
        )
        try {
            $backupStream.Write($bytes, 0, $bytes.Length)
            $backupStream.Flush($true)
        }
        finally {
            $backupStream.Dispose()
        }

        foreach ($entry in $pending) {
            $stream.Position = $entry.PathIdOffset
            $fontBytes = [BitConverter]::GetBytes([long]1553)
            $stream.Write($fontBytes, 0, $fontBytes.Length)
        }
        $stream.Flush($true)

        foreach ($entry in $entries) {
            $stream.Position = $entry.PathIdOffset - 4
            $ptrBytes = [byte[]]::new(12)
            $read = $stream.Read($ptrBytes, 0, $ptrBytes.Length)
            $fileId = [BitConverter]::ToInt32($ptrBytes, 0)
            $fontId = [BitConverter]::ToInt64($ptrBytes, 4)
            if ($read -ne 12 -or $fileId -ne 2 -or $fontId -ne 1553) {
                throw "فشل التحقق بعد التعديل للمكوّن $($entry.Component). النسخة الاحتياطية: $backupPath"
            }
        }
    }
}
finally {
    $stream.Dispose()
}

if ($alreadyInstalled) {
    Write-Output 'الخط العربي مثبت بالفعل في عناصر المهام الستة.'
    exit 0
}

Write-Output 'تم إصلاح مراجع خطوط المهام إلى الخط العربي (1553).'
Write-Output "النسخة الاحتياطية: $backupPath"
