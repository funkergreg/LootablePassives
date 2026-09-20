<#
.SYNOPSIS
    Copies this repo's payload into a Palworld install and registers the mod.

.DESCRIPTION
    Use this to restore the mod after a game update, a Steam verify, or on a new
    machine.

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

    Nothing is deleted: anything already in the destination is left alone. That
    means a file REMOVED from the repo survives in the game folder until it is
    deleted there by hand -- which is how a module deleted from here once went
    on loading in game for days.
    The recovery journal is not in this folder at all -- it lives at the UE4SS
    root, deliberately outside any tree a mod loader reinstalls.

.PARAMETER GameRoot
    Palworld install root. Defaults to the usual Steam location.

.PARAMETER DryRun
    Print what would happen and change nothing.

.EXAMPLE
    .\tools\install.ps1 -DryRun
    .\tools\install.ps1
#>
[CmdletBinding()]
param(
    [string] $GameRoot = "C:\Program Files (x86)\Steam\steamapps\common\Palworld",
    [switch] $DryRun
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

foreach ($t in $targets) {
    Write-Host "  $($t.From)"
    Write-Host "    -> $($t.To)"
    if ($DryRun) { continue }
    New-Item -ItemType Directory -Force -Path $t.To | Out-Null
    Copy-Item -Path (Join-Path $t.From '*') -Destination $t.To -Recurse -Force
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
    Write-Host "Installed. Restart Palworld -- UE4SS hot reload is disabled, so a running game will not pick this up."
}
