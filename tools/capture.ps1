<#
.SYNOPSIS
    Copies the live mod files out of a Palworld install and back into this repo.

.DESCRIPTION
    RESCUE TOOL, not part of the normal loop. The repo is the working copy;
    install.ps1 is the direction you want. Use this only to recover edits that
    were made under the game folder by accident.

    Only the Lua and the PalSchema JSON come back, into Scripts\ and
    PalSchemaMods\LootablePassives\ respectively. Everything under data\ is
    repo-only reference material and is NOT deployed, so there is nothing there
    to capture -- edit those files in the repo.

.PARAMETER GameRoot
    Palworld install root. Defaults to the usual Steam location.

.PARAMETER DryRun
    Print what would happen and change nothing.

.EXAMPLE
    .\tools\capture.ps1
    node tools\luacheck.js
#>
[CmdletBinding()]
param(
    [string] $GameRoot = "C:\Program Files (x86)\Steam\steamapps\common\Palworld",
    [switch] $DryRun
)

$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
$modsDir = Join-Path $GameRoot 'Mods\NativeMods\UE4SS\Mods'
$lua = Join-Path $modsDir 'LootablePassives\Scripts'
$schema = Join-Path $modsDir 'PalSchema\mods\LootablePassives'

foreach ($d in @($lua, $schema)) {
    if (-not (Test-Path $d)) { throw "Not found: '$d'. Is -GameRoot correct?" }
}

function Add-Copies($from, $filter, $repoSubdir) {
    $found = @()
    Get-ChildItem -Path $from -Filter $filter -File -Recurse | ForEach-Object {
        $relative = [IO.Path]::GetRelativePath($from, $_.FullName)
        $found += @{ From = $_.FullName; To = Join-Path $repo (Join-Path $repoSubdir $relative) }
    }
    return $found
}

$copies = @()
$copies += Add-Copies $lua    '*.lua'  'Scripts'
$copies += Add-Copies $schema '*.json' 'PalSchemaMods\LootablePassives'

$changed = 0
foreach ($c in $copies) {
    if (-not (Test-Path $c.From)) { Write-Warning "missing, skipped: $($c.From)"; continue }
    $differs = -not (Test-Path $c.To) -or
    (Get-FileHash $c.From).Hash -ne (Get-FileHash $c.To).Hash
    $state = if ($differs) { 'updated' } else { 'unchanged' }
    Write-Host ("  {0,-9} {1}" -f $state, $c.To.Substring($repo.Length + 1))
    if ($differs) {
        $changed++
        if (-not $DryRun) {
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $c.To) | Out-Null
            Copy-Item -Path $c.From -Destination $c.To -Force
        }
    }
}

Write-Host ""
if ($DryRun) {
    Write-Host "Dry run only. $changed file(s) would change."
}
else {
    Write-Host "$changed file(s) updated. Next: node tools\luacheck.js."
}
