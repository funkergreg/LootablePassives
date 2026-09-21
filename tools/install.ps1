<#
.SYNOPSIS
    Mirrors this repo's payload into a Palworld install and registers the mod.

.DESCRIPTION
    Use this to restore the mod after a game update, a Steam verify, or on a new
    machine, and before every functional test.

    Two destinations, because this mod spans both mod systems:
      Scripts\                        -> Mods\NativeMods\UE4SS\Mods\LootablePassives\Scripts
      PalSchemaMods\LootablePassives\ -> Mods\NativeMods\UE4SS\Mods\PalSchema\mods\LootablePassives

    The repo-side folder is nested as PalSchemaMods\LootablePassives rather than
    a flat PalSchema\ so that Info.json's InstallRule can name it directly: a
    Workshop Targets entry copies the named folder WITH ITS NAME, so "./PalSchema"
    would have installed as PalSchema\mods\PalSchema. The folder name on both
    sides is the PalSchema mod id, and it has to be LootablePassives.

    Registration differs between the two by design. The Lua mod is enabled by a
    line in UE4SS's mods.txt; PalSchema needs no registration at all and loads
    any folder it finds under its mods directory.

    NOTE: the mods.txt handling below is for this manual dev install only. When
    the mod is installed from the Workshop, the official loader writes the
    mods.txt entry itself -- do not "fix" the published package to do it too.

    The install is a MIRROR, and the check that makes it one runs first: every
    file under each destination is compared against the files about to be copied
    there, and a destination file the repo does not have stops the run before
    anything is copied. Such a file goes on loading in game, so a run that left
    it in place would be testing something other than the repo. -Force deletes
    those files (and any directory left empty) instead of stopping.

    Only the two destinations above are examined. Files the game folder holds
    elsewhere -- including LootablePassives\enabled.txt, which is not ours and
    which UE4SS reads as a second way to start a Lua mod -- are not touched.
    The recovery journal is not in this folder at all -- it lives at the UE4SS
    root, deliberately outside any tree a mod loader reinstalls.

.PARAMETER GameRoot
    Palworld install root. Defaults to the usual Steam location.

.PARAMETER DryRun
    Print what would happen and change nothing.

.PARAMETER Force
    Delete destination files the repo does not have, rather than stopping.

.EXAMPLE
    .\tools\install.ps1 -DryRun
    .\tools\install.ps1
    .\tools\install.ps1 -Force
#>
[CmdletBinding()]
param(
    [string] $GameRoot = "C:\Program Files (x86)\Steam\steamapps\common\Palworld",
    [switch] $DryRun,
    [switch] $Force
)

$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
$modsDir = Join-Path $GameRoot 'Mods\NativeMods\UE4SS\Mods'

if (-not (Test-Path $modsDir)) {
    throw "UE4SS mods directory not found at '$modsDir'. Is UE4SS installed, and is -GameRoot correct?"
}

$targets = @(
    @{ From = Join-Path $repo 'Scripts'; To = Join-Path $modsDir 'LootablePassives\Scripts' }
    @{ From = Join-Path $repo 'PalSchemaMods\LootablePassives'; To = Join-Path $modsDir 'PalSchema\mods\LootablePassives' }
)

# Paths of every file under $Root, relative to $Root, or @() when $Root is absent.
function Get-RelativeFiles {
    param([string] $Root)
    if (-not (Test-Path $Root)) { return @() }
    $prefix = (Resolve-Path -LiteralPath $Root).Path.TrimEnd('\') + '\'
    return @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force |
        ForEach-Object { $_.FullName.Substring($prefix.Length) })
}

# Deletes directories under $Root that hold nothing, deepest first, so that a
# folder emptied by the stale sweep does not survive as an empty shell.
function Remove-EmptyDirectories {
    param([string] $Root)
    if (-not (Test-Path $Root)) { return }
    Get-ChildItem -LiteralPath $Root -Recurse -Directory -Force |
        Sort-Object { $_.FullName.Length } -Descending |
        ForEach-Object {
            if (-not (Get-ChildItem -LiteralPath $_.FullName -Force)) {
                Write-Host "    rmdir  $($_.FullName)"
                if (-not $DryRun) { Remove-Item -LiteralPath $_.FullName -Force }
            }
        }
}

# Every destination file with no counterpart in the repo. Collected across BOTH
# targets before anything is copied: the check is worth nothing if the first
# target has already been written when the second one fails it.
$stale = @()
foreach ($t in $targets) {
    $source = @{}
    foreach ($rel in (Get-RelativeFiles $t.From)) { $source[$rel] = $true }
    foreach ($rel in (Get-RelativeFiles $t.To)) {
        if (-not $source.ContainsKey($rel)) {
            $stale += [pscustomobject]@{ To = $t.To; Rel = $rel; Path = (Join-Path $t.To $rel) }
        }
    }
}

if ($stale.Count -gt 0 -and -not $Force) {
    Write-Host ""
    Write-Warning "$($stale.Count) file(s) in the game folder are not in this repo's payload:"
    foreach ($s in $stale) { Write-Host "    $($s.Path)" }
    Write-Host ""
    $msg = "Install stopped before copying anything. The game loads those files, so this install would not be the repo. Re-run with -Force to delete them, or remove them by hand if they belong to something else."
    if ($DryRun) {
        Write-Host $msg
        Write-Host ""
        Write-Host "Dry run only. Nothing was changed."
        return
    }
    Write-Host $msg
    exit 1
}

foreach ($t in $targets) {
    Write-Host "  $($t.From)"
    Write-Host "    -> $($t.To)"
    foreach ($s in ($stale | Where-Object { $_.To -eq $t.To })) {
        Write-Host "    delete $($s.Rel)"
        if (-not $DryRun) { Remove-Item -LiteralPath $s.Path -Force }
    }
    if (-not $DryRun) {
        New-Item -ItemType Directory -Force -Path $t.To | Out-Null
        Copy-Item -Path (Join-Path $t.From '*') -Destination $t.To -Recurse -Force
    }
    Remove-EmptyDirectories $t.To
}

# UE4SS reads mods.txt to decide which Lua mods to start. A missing or ": 0"
# line means the mod is installed but silently inert, which is an easy hour to
# lose, so assert it here rather than trusting it.
$modsTxt = Join-Path $modsDir 'mods.txt'
$entry = 'LootablePassives : 1'
if (Test-Path $modsTxt) {
    $lines = @(Get-Content $modsTxt)
    $found = $lines | Where-Object { $_ -match '^\s*LootablePassives\s*:' }
    if (-not $found) {
        Write-Host "  mods.txt: adding '$entry'"
        if (-not $DryRun) { Add-Content -Path $modsTxt -Value $entry }
    }
    elseif ($found -notmatch ':\s*1\s*$') {
        Write-Host "  mods.txt: enabling (was '$($found -join ', ')')"
        if (-not $DryRun) {
            ($lines | ForEach-Object {
                if ($_ -match '^\s*LootablePassives\s*:') { $entry } else { $_ }
            }) | Set-Content -Path $modsTxt
        }
    }
    else {
        Write-Host "  mods.txt: already enabled"
    }
}
else {
    Write-Warning "mods.txt not found at '$modsTxt'; the Lua mod will not start until it is registered."
}

Write-Host ""
if ($DryRun) {
    Write-Host "Dry run only. Nothing was changed."
}
else {
    if ($stale.Count -gt 0) { Write-Host "Deleted $($stale.Count) file(s) the repo no longer has." }
    Write-Host "Installed. Restart Palworld -- UE4SS hot reload is disabled, so a running game will not pick this up."
}
