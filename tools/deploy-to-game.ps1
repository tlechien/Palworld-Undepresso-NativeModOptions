<#
.SYNOPSIS
    Copies this project's Scripts/ folder into your local UE4SS Mods folder for testing,
    and registers it in mods.txt the same way every other mod is managed.

.DESCRIPTION
    Local UE4SS testing and the Steam Workshop package expect slightly different layouts
    (see README.md). This script bridges the two: it reads PackageName from Info.json,
    finds your Palworld install (Steam auto-detect, or pass -GamePath), and deploys
    Scripts/ into whichever UE4SS Mods folder your install actually uses. Palworld 1.0's
    official Workshop-managed loader uses <Game>\Mods\NativeMods\UE4SS\Mods\ — that's
    checked first. Older manual installs under Pal\Binaries\Win64\ are checked as a
    fallback.

    Deliberately does NOT use the enabled.txt shortcut — that bypasses mods.txt and load
    ordering. Instead it adds "PackageName : 0" to mods.txt (inserted before the Keybinds
    line, which must stay last) if not already present, same as any other mod. Enable it by
    editing mods.txt directly (flip ": 0" to ": 1") — the in-game Options -> Mod Management
    screen only lists Steam Workshop subscriptions, it never scans this folder, so a locally
    deployed dev mod will never appear there no matter what mods.txt says (see
    PALWORLD-MODDING-NOTES.md at the repo root). If an entry already exists, its current
    enabled/disabled state is left untouched on redeploy.

.PARAMETER GamePath
    Path to the Palworld install root (the folder containing the "Pal" folder).
    If omitted, the script tries to auto-detect it via the Steam library.

.EXAMPLE
    .\deploy-to-game.ps1
    .\deploy-to-game.ps1 -GamePath "D:\SteamLibrary\steamapps\common\Palworld"
#>

param(
    [string]$GamePath
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot

$infoJsonPath = Join-Path $ProjectRoot "Info.json"
if (-not (Test-Path $infoJsonPath)) {
    throw "Info.json not found at $infoJsonPath"
}
$info = Get-Content $infoJsonPath -Raw | ConvertFrom-Json
$packageName = $info.PackageName
if ([string]::IsNullOrWhiteSpace($packageName)) {
    throw "PackageName is empty in Info.json"
}

function Find-PalworldInstall {
    $steamPath = (Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -Name "SteamPath" -ErrorAction SilentlyContinue).SteamPath
    if (-not $steamPath) { $steamPath = "C:\Program Files (x86)\Steam" }
    $steamPath = $steamPath -replace "/", "\"

    $libraryFolders = @($steamPath)
    $vdfPath = Join-Path $steamPath "steamapps\libraryfolders.vdf"
    if (Test-Path $vdfPath) {
        $vdfContent = Get-Content $vdfPath -Raw
        $matches = [regex]::Matches($vdfContent, '"path"\s*"([^"]+)"')
        foreach ($m in $matches) {
            $libraryFolders += ($m.Groups[1].Value -replace "\\\\", "\")
        }
    }

    foreach ($lib in $libraryFolders | Select-Object -Unique) {
        $candidate = Join-Path $lib "steamapps\common\Palworld"
        if (Test-Path (Join-Path $candidate "Pal")) {
            return $candidate
        }
    }
    return $null
}

if (-not $GamePath) {
    Write-Host "No -GamePath given, attempting Steam auto-detect..."
    $GamePath = Find-PalworldInstall
    if (-not $GamePath) {
        throw "Couldn't auto-detect Palworld. Re-run with -GamePath `"<path to Palworld folder>`"."
    }
    Write-Host "Found Palworld install: $GamePath"
}

$win64 = Join-Path $GamePath "Pal\Binaries\Win64"

$candidateModRoots = @(
    (Join-Path $GamePath "Mods\NativeMods\UE4SS\Mods"),
    (Join-Path $win64 "Mods"),
    (Join-Path $win64 "ue4ss\Mods")
)
$modsRoot = $candidateModRoots | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $modsRoot) {
    throw "No UE4SS Mods folder found (checked: $($candidateModRoots -join ', ')). Install UE4SS first: https://steamcommunity.com/sharedfiles/filedetails/?id=3625223587"
}
Write-Host "Using UE4SS Mods folder: $modsRoot"

$targetModDir = Join-Path $modsRoot $packageName
$targetScripts = Join-Path $targetModDir "Scripts"

New-Item -ItemType Directory -Force -Path $targetScripts | Out-Null
Copy-Item -Path (Join-Path $ProjectRoot "Scripts\*") -Destination $targetScripts -Recurse -Force

$modsTxtPath = Join-Path $modsRoot "mods.txt"
$modsTxtLines = @()
if (Test-Path $modsTxtPath) {
    $modsTxtLines = @(Get-Content -LiteralPath $modsTxtPath)
}

$alreadyListed = $modsTxtLines | Where-Object { $_ -match "^\s*$([regex]::Escape($packageName))\s*:" }
if ($alreadyListed) {
    Write-Host "'$packageName' already present in mods.txt, leaving its enabled/disabled state as-is."
} else {
    $keybindsLineIndex = -1
    for ($i = 0; $i -lt $modsTxtLines.Count; $i++) {
        if ($modsTxtLines[$i] -match "^\s*Keybinds\s*:") { $keybindsLineIndex = $i; break }
    }
    $newEntry = "$packageName : 0"
    if ($keybindsLineIndex -ge 0) {
        # Insert before the "Built-in keybinds, do not move up!" comment if present, else before Keybinds itself.
        $insertAt = $keybindsLineIndex
        if ($insertAt -gt 0 -and $modsTxtLines[$insertAt - 1] -match "Keybinds.*do not move up") {
            $insertAt = $insertAt - 1
        }
        $modsTxtLines = $modsTxtLines[0..($insertAt - 1)] + $newEntry + $modsTxtLines[$insertAt..($modsTxtLines.Count - 1)]
    } else {
        $modsTxtLines += $newEntry
    }
    Set-Content -LiteralPath $modsTxtPath -Value $modsTxtLines
    Write-Host "Added '$newEntry' to mods.txt (disabled by default -- flip the ': 0' to ': 1' in mods.txt directly to enable it; the in-game Options > Mod Management screen only shows Steam Workshop subscriptions, it won't show this)."
}

Write-Host "Deployed '$packageName' to $targetModDir"
Write-Host "Launch Palworld to test. Check UE4SS.log in $(Split-Path -Parent $modsRoot) if it doesn't load."
