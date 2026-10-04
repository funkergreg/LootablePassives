<#
.SYNOPSIS
    Copies the shippable half of this repo into a Palworld Mod Uploader item folder.

.DESCRIPTION
    Steam UGC uploads the item folder recursively, so the repo cannot be uploaded
    in place: without this step every subscriber would download .git\, tools\ and
    docs\ as well. This stages an ALLOWLIST and nothing else, so a new top-level
    folder in the repo cannot leak by default -- adding one to the package has to
    be a deliberate edit here.

    Staged:
      Info.json, thumbnail.png, LICENSE,
      Scripts\, PalSchemaMods\LootablePassives\

    README.md is not staged: it documents the GitHub development repo, not the
    shipped mod. The Workshop page text is .docs\workshop-description.txt, which
    is pasted into the Workshop page by hand and is not staged either.

    The destination is the numbered folder the uploader's Create New Mod made
    under the Workshop content directory. Its name is the Steam item id, and the
    .workshop.json inside it holds the Published ID -- that file is the
    uploader's and is never written or deleted here.

    Like install.ps1 this is a MIRROR, built on the same helpers in
    tools\mirror.ps1, and the same check runs first: a file in
    the destination that the staged set does not have stops the run before
    anything is copied. Left alone it would be uploaded to subscribers. -Force
    deletes those files, and any directory left empty, instead of stopping.

    Four checks run before anything is copied, because the uploader validates
    almost nothing and everything it misses fails SILENTLY after a clean upload:
      - Info.json parses
      - PackageName is non-empty and alphanumeric
      - every Tag is one the platform defines
      - every InstallRule Type is one the loader knows, and every Targets path,
        plus Thumbnail, exists in what is about to be staged

    Keep those here. Do not grow a second verifier tool.

.PARAMETER ItemId
    The numbered item folder under the Workshop content directory.

.PARAMETER Destination
    The item folder in full, instead of -ItemId.

.PARAMETER WorkshopRoot
    Workshop content directory. Defaults to the path the uploader recorded in its
    own workshop_path.txt, and to the usual Steam location if that is absent.

.PARAMETER DryRun
    Print what would happen and change nothing.

.PARAMETER Force
    Delete destination files the staged set does not have, rather than stopping.

.EXAMPLE
    .\tools\stage.ps1 -ItemId 3799999999 -DryRun
    .\tools\stage.ps1 -ItemId 3799999999
#>
[CmdletBinding()]
param(
    [string] $ItemId,
    [string] $Destination,
    [string] $WorkshopRoot,
    [switch] $DryRun,
    [switch] $Force
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'mirror.ps1')

$repo = Split-Path -Parent $PSScriptRoot

# Everything that ships, and nothing else. Relative to the repo root; a folder is
# staged recursively under the same relative path, which is what keeps
# PalSchemaMods\LootablePassives matching the InstallRule that names it.
$ALLOWLIST = @(
    'Info.json'
    'thumbnail.png'
    'LICENSE'
    'Scripts'
    'PalSchemaMods\LootablePassives'
)

# The uploader's own file. Never written, never deleted, never counted as stale.
$UPLOADER_OWNED = @('.workshop.json')

# 02-Package.md: the only tags the platform defines.
$LEGAL_TAGS = @(
    'PalSchema', 'UE4SS', 'Model Replacement', 'Utilities', 'Gameplay', 'User Interface'
)

# 04-Tech.md: the only install types.
$LEGAL_TYPES = @('UE4SS', 'Lua', 'PalSchema', 'LogicMods', 'Paks')

#-------------------------------------------------------------------------------
# Where it is going
#-------------------------------------------------------------------------------

if (-not $Destination) {
    if (-not $ItemId) {
        throw "Give -ItemId (the numbered folder made by the uploader's Create New Mod) or -Destination."
    }
    if (-not $WorkshopRoot) {
        # The uploader records the directory it is pointed at; prefer that over guessing.
        $recorded = 'C:\Program Files (x86)\Steam\steamapps\common\PalworldModUploader\workshop_path.txt'
        if (Test-Path $recorded) {
            $WorkshopRoot = (Get-Content $recorded -Raw).Trim()
        }
        else {
            $WorkshopRoot = 'C:\Program Files (x86)\Steam\steamapps\workshop\content\1623730'
        }
    }
    $Destination = Join-Path $WorkshopRoot $ItemId
}

if (-not (Test-Path $Destination)) {
    throw "Item folder not found at '$Destination'. Make it with the uploader's Create New Mod first; the folder name is the Steam item id."
}

#-------------------------------------------------------------------------------
# Read and check Info.json before anything is copied
#-------------------------------------------------------------------------------

$infoPath = Join-Path $repo 'Info.json'
if (-not (Test-Path $infoPath)) {
    throw "Info.json not found at '$infoPath'."
}
try {
    $info = Get-Content $infoPath -Raw | ConvertFrom-Json
}
catch {
    throw "Info.json does not parse: $($_.Exception.Message)"
}

$problems = @()

if ([string]::IsNullOrWhiteSpace([string]$info.PackageName)) {
    $problems += "PackageName is empty."
}
elseif ([string]$info.PackageName -notmatch '^[A-Za-z0-9]+$') {
    $problems += "PackageName '$($info.PackageName)' is not alphanumeric; the uploader rejects it."
}

foreach ($tag in @($info.Tags)) {
    if ($LEGAL_TAGS -notcontains $tag) {
        $problems += "Tag '$tag' is not one the platform defines. It uploads cleanly and then does nothing."
    }
}

if (@($info.InstallRule).Count -lt 1) {
    $problems += "No InstallRule. The uploader rejects the package."
}

# Every Targets path has to resolve inside what is about to be staged, not merely
# inside the repo: a path that only exists in the repo installs as nothing, with
# no error anywhere a player would see.
$stagedRelative = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($entry in $ALLOWLIST) {
    $source = Join-Path $repo $entry
    if (-not (Test-Path $source)) {
        $problems += "Allowlisted '$entry' is missing from the repo."
        continue
    }
    [void]$stagedRelative.Add($entry)
    if (Test-Path $source -PathType Container) {
        foreach ($rel in (Get-RelativePaths $source -IncludeDirectories)) {
            [void]$stagedRelative.Add((Join-Path $entry $rel))
        }
    }
}

# A Targets or Thumbnail path from Info.json as a repo-relative Windows path.
function ConvertTo-RepoRelative {
    param([string] $Path)
    return ($Path -replace '^\./', '') -replace '/', '\'
}

# The loader appends {PackageName} to the type's directory and THEN copies each
# Targets folder in under its own name. A target whose leaf is the package name
# therefore installs as PackageName\PackageName\..., which loads as nothing and
# reports nothing.
$targetPrefixes = @()
foreach ($rule in @($info.InstallRule)) {
    if ($LEGAL_TYPES -notcontains [string]$rule.Type) {
        $problems += "InstallRule Type '$($rule.Type)' is not one the loader knows."
    }
    foreach ($target in @($rule.Targets)) {
        $relative = ConvertTo-RepoRelative $target
        $targetPrefixes += $relative
        if (-not $stagedRelative.Contains($relative)) {
            $problems += "InstallRule Targets '$target' is not in the staged set."
        }
        if ((Split-Path -Leaf $relative) -eq $info.PackageName) {
            $problems += "InstallRule Targets '$target' ends in the package name, so it installs as '$($info.PackageName)\$($info.PackageName)'. Name the folders INSIDE it instead."
        }
    }
}

# Anything staged that no Targets path covers is shipped and never installed.
# Package metadata -- the allowlisted files -- is read from the item folder
# itself and is not installed.
$METADATA = @($ALLOWLIST | Where-Object { Test-Path (Join-Path $repo $_) -PathType Leaf })
foreach ($relative in $stagedRelative) {
    if ($METADATA -contains $relative) { continue }
    if (Test-Path (Join-Path $repo $relative) -PathType Container) { continue }
    $covered = $false
    foreach ($prefix in $targetPrefixes) {
        if ($relative -eq $prefix -or $relative.StartsWith($prefix + '\', [StringComparison]::OrdinalIgnoreCase)) {
            $covered = $true
            break
        }
    }
    if (-not $covered) {
        $problems += "'$relative' is staged but no InstallRule Targets path covers it, so it ships and is never installed."
    }
}

$thumbnail = [string]$info.Thumbnail
if ([string]::IsNullOrWhiteSpace($thumbnail)) {
    $problems += "Thumbnail is empty."
}
elseif (-not $stagedRelative.Contains((ConvertTo-RepoRelative $thumbnail))) {
    $problems += "Thumbnail '$thumbnail' is not in the staged set."
}

if ($problems.Count -gt 0) {
    Write-Host ""
    foreach ($problem in $problems) { Write-Warning $problem }
    Write-Host ""
    Write-Host "Nothing was staged. Every item above uploads cleanly and then fails silently, which is why they are checked here."
    exit 1
}

#-------------------------------------------------------------------------------
# Whose folder is this
#-------------------------------------------------------------------------------

$existingInfo = Join-Path $Destination 'Info.json'
if ((Test-Path $existingInfo) -and -not $Force) {
    $theirs = $null
    try { $theirs = (Get-Content $existingInfo -Raw | ConvertFrom-Json).PackageName } catch { }
    # MyAwesomeMod is what Create New Mod writes into a fresh folder.
    if ($theirs -and $theirs -ne $info.PackageName -and $theirs -ne 'MyAwesomeMod') {
        Write-Host ""
        Write-Warning "'$Destination' already holds a package named '$theirs', not '$($info.PackageName)'."
        Write-Host "Staging would overwrite it. Check the item id. -Force proceeds anyway."
        exit 1
    }
}

$workshopMeta = Join-Path $Destination '.workshop.json'
if (-not (Test-Path $workshopMeta)) {
    Write-Warning "No .workshop.json in '$Destination', so this folder has no Published ID and Upload To Steam will not run on it. A folder made with Shift+Create New Mod is local only."
}
else {
    # The loader compares Version as a plain string, so an unchanged one is not
    # seen as an update at all.
    try {
        $lastVersion = (Get-Content $workshopMeta -Raw | ConvertFrom-Json).Version
        if ($lastVersion -and $lastVersion -eq $info.Version) {
            Write-Warning "Version '$($info.Version)' is the same as the last upload. Palworld will not treat this as an update; bump Version in Info.json."
        }
    }
    catch { }
}

#-------------------------------------------------------------------------------
# Mirror
#-------------------------------------------------------------------------------

$stale = @()
foreach ($relative in (Get-RelativePaths $Destination)) {
    if ($UPLOADER_OWNED -contains $relative) { continue }
    if (-not $stagedRelative.Contains($relative)) {
        $stale += [pscustomobject]@{ Rel = $relative; Path = (Join-Path $Destination $relative) }
    }
}

if ($stale.Count -gt 0 -and -not $Force) {
    Stop-OnStale -DryRun:$DryRun `
        -Heading "$($stale.Count) file(s) in the item folder are not in this package:" `
        -Listing @($stale | ForEach-Object { $_.Rel }) `
        -Message "Staging stopped before copying anything. Those files would be uploaded to every subscriber. Re-run with -Force to delete them."
}

Write-Host "  $repo"
Write-Host "    -> $Destination"

# Printed because getting this wrong is silent in game: the mod appears in the
# manager, installs, and does nothing. The package-name level is asserted for
# Lua and PalSchema only.
Write-Host ""
Write-Host "  Installs as:"
foreach ($rule in @($info.InstallRule)) {
    if ($rule.IsServer) { continue }
    $base = switch ([string]$rule.Type) {
        'Lua'       { "Mods\NativeMods\UE4SS\Mods\$($info.PackageName)" }
        'PalSchema' { "Mods\NativeMods\UE4SS\Mods\PalSchema\mods\$($info.PackageName)" }
        'UE4SS'     { "Mods\NativeMods\UE4SS  (package-name level unverified)" }
        'LogicMods' { "Pal\Content\Paks\LogicMods  (package-name level unverified)" }
        'Paks'      { "Pal\Content\Paks\~WorkshopMods  (package-name level unverified)" }
        default     { "<unknown type>" }
    }
    foreach ($target in @($rule.Targets)) {
        $leaf = Split-Path -Leaf (ConvertTo-RepoRelative $target)
        Write-Host "    $base\$leaf\"
    }
}
Write-Host ""

foreach ($s in $stale) {
    Write-Host "    delete $($s.Rel)"
    if (-not $DryRun) { Remove-Item -LiteralPath $s.Path -Force }
}

foreach ($entry in $ALLOWLIST) {
    $source = Join-Path $repo $entry
    $target = Join-Path $Destination $entry
    Write-Host "    stage  $entry"
    if ($DryRun) { continue }
    if (Test-Path $source -PathType Container) {
        New-Item -ItemType Directory -Force -Path $target | Out-Null
        Copy-Item -Path (Join-Path $source '*') -Destination $target -Recurse -Force
    }
    else {
        $parent = Split-Path -Parent $target
        if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
        Copy-Item -LiteralPath $source -Destination $target -Force
    }
}

Remove-EmptyDirectories $Destination -DryRun:$DryRun

Write-Host ""
if ($DryRun) {
    Write-Host "Dry run only. Nothing was changed."
}
else {
    if ($stale.Count -gt 0) { Write-Host "Deleted $($stale.Count) file(s) the package no longer has." }
    Write-Host "Staged $($info.PackageName) $($info.Version). Upload it from Palworld Mod Uploader, then set visibility on the Workshop page and paste .docs\workshop-description.txt into its description if that file changed."
}
