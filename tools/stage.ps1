<#
.SYNOPSIS
    Bumps the version and sets DebugMode in the repo's Info.json, then copies
    the shippable half of this repo into its Workshop item folder, ready for
    Upload To Steam.

.DESCRIPTION
    The repo reaches the game only through the item folder. At every launch
    Palworld's official mod loader compares Version in the item folder's
    Info.json with the installed copy in Mods\ManagedMods\<PackageName>, as
    plain strings, and reinstalls from the item folder when they differ or when
    DebugMode is true (04-Tech.md). Reinstalling removes what
    ManagedMods\<PackageName>\InstallManifest.json lists and copies the
    InstallRule Targets in again. A subscribed machine reinstalls the same way
    after Steam downloads an upload.

    The item folder is made once, by Palworld Mod Uploader's Create New Mod.
    The uploader's Save Info.json writes the item folder's Info.json, and the
    next stage overwrites it with the repo's: edit Info.json in the repo.

    Every run that stages rewrites Version (<major>.<minor>.<patch>) and
    DebugMode in the REPO's Info.json, then stages that file verbatim:
      default    patch + 1, DebugMode true. A dev build.
      -Publish   minor + 1, patch 0, DebugMode false. A release.
    Only a release has patch 0. -DryRun prints the next version and writes
    nothing. A run stopped by a check or by stale files writes nothing either.

    What is staged is read from Info.json, and nothing else is:
      Info.json, the Thumbnail file, LICENSE when the repo has one, and every
      InstallRule Targets path, client and server.
    A Targets path missing from the repo is warned about and skipped. README,
    tools, .git and any other repo file no Targets path names stay behind.

    The script holds nothing specific to one mod: copied into another mod's
    repo as tools\stage.ps1, it stages that repo by its own Info.json.

    The item folder is found, not named: it is the one folder under the
    Workshop content directory whose Info.json has this repo's PackageName. None
    or several stops the run. The .workshop.json inside it holds the Published
    ID; that file is the uploader's and is never written or deleted here.

    This is a MIRROR, and the check that makes it one runs first: a file in the
    item folder that the staged set does not have stops the run before anything
    is copied. Left alone it would be uploaded to subscribers. -Force deletes
    those files, and any directory left empty, instead of stopping.

    Six checks run on the repo's Info.json before anything is copied, because
    the uploader validates almost nothing and everything it misses fails
    SILENTLY after a clean upload:
      - Info.json parses
      - PackageName is non-empty and alphanumeric
      - Version appears once, as <major>.<minor>.<patch>
      - DebugMode appears once, as true or false
      - every Tag is one the platform defines
      - every InstallRule Type is one the loader knows, and no Targets path is
        the package root, outside the repo, or a folder named after the
        package under Lua or PalSchema; Thumbnail is a file in the repo

    Keep those here. Do not grow a second verifier tool.

    Mods\PalModSettings.ini is read, never written: a warning is printed when
    bGlobalEnableMod is not True, or when no ActiveModList line names the
    package or one of its Dependencies, since the loader installs nothing in
    either case. The loader writes UE4SS's mods.txt entry itself.

.PARAMETER Publish
    Stage a release: minor + 1, patch 0, DebugMode false.

.PARAMETER GameRoot
    Palworld install root. Defaults to the usual Steam location.

.PARAMETER WorkshopRoot
    Workshop content directory. Defaults to WorkshopRootDir in
    PalModSettings.ini, then to the path the uploader recorded in its own
    workshop_path.txt, then to the usual Steam location.

.PARAMETER DryRun
    Print what would happen and change nothing.

.PARAMETER Force
    Delete item-folder files the staged set does not have, rather than stopping.

.EXAMPLE
    .\tools\stage.ps1 -DryRun
    .\tools\stage.ps1
    .\tools\stage.ps1 -Publish
#>
[CmdletBinding()]
param(
    [switch] $Publish,
    [string] $GameRoot = "C:\Program Files (x86)\Steam\steamapps\common\Palworld",
    [string] $WorkshopRoot,
    [switch] $DryRun,
    [switch] $Force
)

$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot

# The uploader's own file. Never written, never deleted, never counted as stale.
$UPLOADER_OWNED = @('.workshop.json')

# 02-Package.md: the only tags the platform defines.
$LEGAL_TAGS = @(
    'PalSchema', 'UE4SS', 'Model Replacement', 'Utilities', 'Gameplay', 'User Interface'
)

# 04-Tech.md: the only install types.
$LEGAL_TYPES = @('UE4SS', 'Lua', 'PalSchema', 'LogicMods', 'Paks')

# Matches the Version member with a <major>.<minor>.<patch> value. Group 1 is
# everything up to the opening quote, groups 2-4 the numbers, group 5 the
# closing quote.
$VERSION_MEMBER = '("Version"\s*:\s*")(\d+)\.(\d+)\.(\d+)(")'

# Matches the DebugMode member with a boolean value; group 1 is everything
# before the value.
$DEBUG_MEMBER = '("DebugMode"\s*:\s*)(true|false)'

#-------------------------------------------------------------------------------
# Mirror helpers
#-------------------------------------------------------------------------------

# Paths of every file under $Root, relative to $Root, or @() when $Root is
# absent.
function Get-RelativePaths {
    param([string] $Root)
    if (-not (Test-Path $Root)) { return @() }
    $prefix = (Resolve-Path -LiteralPath $Root).Path.TrimEnd('\') + '\'
    return @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force |
        ForEach-Object { $_.FullName.Substring($prefix.Length) })
}

# Every file under $Destination whose relative path $Keep does not contain, as
# objects with Rel and Path. $Keep is anything with a Contains method. Relative
# paths in $Exclude are skipped.
function Get-StaleFiles {
    param(
        [string] $Destination,
        $Keep,
        [string[]] $Exclude = @()
    )
    $stale = @()
    foreach ($rel in (Get-RelativePaths $Destination)) {
        if ($Exclude -contains $rel) { continue }
        if (-not $Keep.Contains($rel)) {
            $stale += [pscustomobject]@{ Rel = $rel; Path = (Join-Path $Destination $rel) }
        }
    }
    return $stale
}

# Prints and deletes each entry of $Stale, as Get-StaleFiles returns them. Under
# -DryRun it prints and deletes nothing.
function Remove-StaleFiles {
    param(
        [object[]] $Stale,
        [switch] $DryRun
    )
    foreach ($s in $Stale) {
        Write-Host "    delete $($s.Rel)"
        if (-not $DryRun) { Remove-Item -LiteralPath $s.Path -Force }
    }
}

# Creates $To if needed and copies everything under $From into it, overwriting.
function Copy-DirectoryContents {
    param(
        [string] $From,
        [string] $To
    )
    New-Item -ItemType Directory -Force -Path $To | Out-Null
    Copy-Item -Path (Join-Path $From '*') -Destination $To -Recurse -Force
}

# Deletes directories under $Root that hold nothing, deepest first. Under
# -DryRun it prints what it would delete and deletes nothing.
function Remove-EmptyDirectories {
    param(
        [string] $Root,
        [switch] $DryRun
    )
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

#-------------------------------------------------------------------------------
# Read and check Info.json before anything is copied
#-------------------------------------------------------------------------------

$infoPath = Join-Path $repo 'Info.json'
if (-not (Test-Path $infoPath)) {
    throw "Info.json not found at '$infoPath'."
}
$infoText = [System.IO.File]::ReadAllText($infoPath)
try {
    $info = $infoText | ConvertFrom-Json
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

$versionMatches = [regex]::Matches($infoText, $VERSION_MEMBER)
if ($versionMatches.Count -ne 1) {
    $problems += "Version '$($info.Version)' must appear exactly once, as <major>.<minor>.<patch> with whole numbers, for it to be incremented."
}

if ([regex]::Matches($infoText, $DEBUG_MEMBER).Count -ne 1) {
    $problems += "DebugMode must appear exactly once, as true or false, for it to be set."
}

foreach ($tag in @($info.Tags)) {
    if ($LEGAL_TAGS -notcontains $tag) {
        $problems += "Tag '$tag' is not one the platform defines. It uploads cleanly and then does nothing."
    }
}

if (@($info.InstallRule).Count -lt 1) {
    $problems += "No InstallRule. The uploader rejects the package."
}

# A Targets or Thumbnail path from Info.json as a repo-relative Windows path with
# no trailing separator. '.' and './' become '', the package root.
function ConvertTo-RepoRelative {
    param([string] $Path)
    return (($Path -replace '^\.(/|$)', '') -replace '/', '\').TrimEnd('\')
}

# True when the loader copies a target's contents rather than the folder itself:
# a Targets path ending in '/', or the package root '.'.
function Test-ContentsTarget {
    param([string] $Path)
    return ($Path -match '/$' -or $Path -match '^\.?$')
}

# How the loader places a target, as the InstallManifest.json files it writes
# record it: a Targets path with no trailing '/' is copied as a folder under its
# own leaf name; one ending in '/', or '.', has its contents copied. Lua and
# PalSchema first add a {PackageName} folder to the type's directory; UE4SS and
# LogicMods do not; Paks is unrecorded. A folder target whose leaf is the package
# name therefore installs under Lua or PalSchema as PackageName\PackageName\...,
# which loads as nothing and reports nothing.
$PACKAGE_LEVEL_TYPES = @('Lua', 'PalSchema')

# What ships, as repo-relative paths: Info.json, the Thumbnail, LICENSE when the
# repo has one, and every InstallRule Targets path, client and server. Nothing
# else in the repo is staged.
$ship = @('Info.json')
$warnings = @()

$thumbnail = ConvertTo-RepoRelative ([string]$info.Thumbnail)
if (-not $thumbnail) {
    $problems += "Thumbnail is empty."
}
elseif (-not (Test-Path -LiteralPath (Join-Path $repo $thumbnail) -PathType Leaf)) {
    $problems += "Thumbnail '$($info.Thumbnail)' is not a file in the repo."
}
else {
    $ship += $thumbnail
}

if (Test-Path -LiteralPath (Join-Path $repo 'LICENSE') -PathType Leaf) { $ship += 'LICENSE' }

foreach ($rule in @($info.InstallRule)) {
    if ($LEGAL_TYPES -notcontains [string]$rule.Type) {
        $problems += "InstallRule Type '$($rule.Type)' is not one the loader knows."
    }
    foreach ($target in @($rule.Targets)) {
        $relative = ConvertTo-RepoRelative $target
        if (-not $relative) {
            $problems += "InstallRule Targets '$target' is the package root. Staged from a repo, that ships .git, tools and every other dev file; name the folders to ship instead."
            continue
        }
        if ([System.IO.Path]::IsPathRooted($relative) -or $relative -match '(^|\\)\.\.(\\|$)') {
            $problems += "InstallRule Targets '$target' points outside the repo."
            continue
        }
        if (-not (Test-ContentsTarget $target) -and
            $PACKAGE_LEVEL_TYPES -contains [string]$rule.Type -and
            (Split-Path -Leaf $relative) -eq $info.PackageName) {
            $problems += "InstallRule Targets '$target' ends in the package name, so it installs as '$($info.PackageName)\$($info.PackageName)'. Name the folders INSIDE it, or end the path in '/' to copy its contents."
        }
        if (-not (Test-Path -LiteralPath (Join-Path $repo $relative))) {
            $warnings += "InstallRule Targets '$target' does not exist in the repo, so nothing is staged or installed for it. Add it, or remove it from Info.json."
            continue
        }
        if ($ship -notcontains $relative) { $ship += $relative }
    }
}

# Every file the stage writes, relative to the item folder. The stale check keeps
# these and nothing else.
$stagedRelative = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($entry in $ship) {
    $source = Join-Path $repo $entry
    if (Test-Path -LiteralPath $source -PathType Container) {
        foreach ($rel in (Get-RelativePaths $source)) {
            [void]$stagedRelative.Add((Join-Path $entry $rel))
        }
    }
    elseif (Test-Path -LiteralPath $source -PathType Leaf) {
        [void]$stagedRelative.Add($entry)
    }
}

foreach ($warning in $warnings) { Write-Warning $warning }

if ($problems.Count -gt 0) {
    Write-Host ""
    foreach ($problem in $problems) { Write-Warning $problem }
    Write-Host ""
    Write-Host "Nothing was staged. Every item above uploads cleanly and then fails silently, which is why they are checked here."
    exit 1
}

# The version and DebugMode this run stages, and the repo's Info.json text with
# both in place of the old values. -Publish: minor + 1, patch 0, DebugMode false.
# Otherwise: patch + 1, DebugMode true.
$v = $versionMatches[0].Groups
$major = [int]$v[2].Value
$minor = [int]$v[3].Value
$patch = [int]$v[4].Value
if ($Publish) {
    $newVersion = "$major.$($minor + 1).0"
    $newDebug = 'false'
}
else {
    $newVersion = "$major.$minor.$($patch + 1)"
    $newDebug = 'true'
}
$newInfoText = [regex]::Replace($infoText, $VERSION_MEMBER, '${1}' + $newVersion + '${5}')
$newInfoText = [regex]::Replace($newInfoText, $DEBUG_MEMBER, '${1}' + $newDebug)

#-------------------------------------------------------------------------------
# Where it is going
#-------------------------------------------------------------------------------

# PalModSettings.ini as a list of lines, or @() when absent.
$settingsPath = Join-Path $GameRoot 'Mods\PalModSettings.ini'
$settings = @()
if (Test-Path $settingsPath) { $settings = @(Get-Content $settingsPath) }

if (-not $WorkshopRoot) {
    $fromSettings = $settings | Where-Object { $_ -match '^\s*WorkshopRootDir\s*=' } | Select-Object -First 1
    $recorded = 'C:\Program Files (x86)\Steam\steamapps\common\PalworldModUploader\workshop_path.txt'
    if ($fromSettings) {
        $WorkshopRoot = ($fromSettings -replace '^\s*WorkshopRootDir\s*=', '').Trim()
    }
    elseif (Test-Path $recorded) {
        $WorkshopRoot = (Get-Content $recorded -Raw).Trim()
    }
    else {
        $WorkshopRoot = 'C:\Program Files (x86)\Steam\steamapps\workshop\content\1623730'
    }
}

if (-not (Test-Path $WorkshopRoot)) {
    throw "Workshop content directory not found at '$WorkshopRoot'. Give -WorkshopRoot."
}

# Every folder under WorkshopRoot whose Info.json names this PackageName.
$found = @()
foreach ($dir in (Get-ChildItem -LiteralPath $WorkshopRoot -Directory -Force)) {
    $candidate = Join-Path $dir.FullName 'Info.json'
    if (-not (Test-Path $candidate)) { continue }
    $name = $null
    try { $name = (Get-Content $candidate -Raw | ConvertFrom-Json).PackageName } catch { }
    if ($name -eq $info.PackageName) { $found += $dir.FullName }
}

if ($found.Count -eq 0) {
    throw "No folder under '$WorkshopRoot' has an Info.json with PackageName '$($info.PackageName)'. Make one with the uploader's Create New Mod, then set Package Name to '$($info.PackageName)' and Save Info.json (a fresh folder says 'MyAwesomeMod')."
}
if ($found.Count -gt 1) {
    Write-Host ""
    Write-Warning "$($found.Count) folders under '$WorkshopRoot' have PackageName '$($info.PackageName)':"
    foreach ($m in $found) { Write-Host "    $m" }
    Write-Host ""
    Write-Host "The loader enables only one of them, and which one is not defined. Remove or rename the others; nothing was staged."
    exit 1
}
$Destination = $found[0]

$workshopMeta = Join-Path $Destination '.workshop.json'
if (-not (Test-Path $workshopMeta)) {
    Write-Warning "No .workshop.json in '$Destination', so this folder has no Published ID and Upload To Steam will not run on it. A folder made with Shift+Create New Mod is local only."
}
else {
    # The loader compares Version as a plain string, so a version equal to the
    # last upload is not seen as an update on a subscribed machine.
    try {
        $lastVersion = (Get-Content $workshopMeta -Raw | ConvertFrom-Json).last_published_version
        if ($lastVersion -and $lastVersion -eq $newVersion) {
            Write-Warning "Version '$newVersion' is the same as the last upload, so subscribed machines will not reinstall it. Raise Version in Info.json past '$lastVersion'."
        }
    }
    catch { }
}

#-------------------------------------------------------------------------------
# Mirror
#-------------------------------------------------------------------------------

$stale = @(Get-StaleFiles -Destination $Destination -Keep $stagedRelative -Exclude $UPLOADER_OWNED)

if ($stale.Count -gt 0 -and -not $Force) {
    Write-Host ""
    Write-Warning "$($stale.Count) file(s) in the item folder are not in this package:"
    foreach ($s in $stale) { Write-Host "    $($s.Rel)" }
    Write-Host ""
    Write-Host "Staging stopped before copying anything. Those files would be uploaded to every subscriber. Re-run with -Force to delete them."
    if ($DryRun) {
        Write-Host ""
        Write-Host "Dry run only. Nothing was changed."
        exit 0
    }
    exit 1
}

Write-Host "  $repo"
Write-Host "    -> $Destination"
Write-Host ""
$kind = if ($Publish) { 'release' } else { 'dev build' }
Write-Host "  $kind  Version $($info.Version) -> $newVersion, DebugMode $($info.DebugMode.ToString().ToLower()) -> $newDebug"

# Prints, for each client InstallRule target, the game directory it lands in,
# by the placement rules in the comment on $PACKAGE_LEVEL_TYPES. Paks is marked
# unrecorded.
Write-Host ""
Write-Host "  Installs as:"
foreach ($rule in @($info.InstallRule)) {
    if ($rule.IsServer) { continue }
    $base = switch ([string]$rule.Type) {
        'Lua'       { "Mods\NativeMods\UE4SS\Mods\$($info.PackageName)" }
        'PalSchema' { "Mods\NativeMods\UE4SS\Mods\PalSchema\mods\$($info.PackageName)" }
        'UE4SS'     { "Mods\NativeMods\UE4SS" }
        'LogicMods' { "Pal\Content\Paks\LogicMods" }
        'Paks'      { "Pal\Content\Paks\~WorkshopMods  (package-name level unrecorded)" }
        default     { "<unknown type>" }
    }
    foreach ($target in @($rule.Targets)) {
        if (Test-ContentsTarget $target) {
            Write-Host "    $base\  (contents of '$target')"
        }
        else {
            $leaf = Split-Path -Leaf (ConvertTo-RepoRelative $target)
            Write-Host "    $base\$leaf\"
        }
    }
}
Write-Host ""

# The repo's Info.json takes the new values first, so the copy below stages it.
Write-Host "    write  Info.json Version $newVersion, DebugMode $newDebug"
if (-not $DryRun) {
    [System.IO.File]::WriteAllText($infoPath, $newInfoText, (New-Object System.Text.UTF8Encoding $false))
}

Remove-StaleFiles -Stale $stale -DryRun:$DryRun

foreach ($entry in $ship) {
    $source = Join-Path $repo $entry
    $target = Join-Path $Destination $entry
    Write-Host "    stage  $entry"
    if ($DryRun) { continue }
    if (Test-Path $source -PathType Container) {
        Copy-DirectoryContents -From $source -To $target
    }
    else {
        $parent = Split-Path -Parent $target
        if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
        Copy-Item -LiteralPath $source -Destination $target -Force
    }
}

Remove-EmptyDirectories $Destination -DryRun:$DryRun

#-------------------------------------------------------------------------------
# Will the loader install it
#-------------------------------------------------------------------------------

if ($settings.Count -eq 0) {
    Write-Warning "PalModSettings.ini not found at '$settingsPath'. Start Palworld once and enable the mod under Options -> Mod Management."
}
else {
    if (-not ($settings | Where-Object { $_ -match '^\s*bGlobalEnableMod\s*=\s*True\s*$' })) {
        Write-Warning "PalModSettings.ini does not set bGlobalEnableMod=True, so the loader installs no mods. Turn mods on under Options -> Mod Management."
    }
    if (-not ($settings | Where-Object { $_ -match "^\s*ActiveModList\s*=\s*$([regex]::Escape($info.PackageName))\s*$" })) {
        Write-Warning "PalModSettings.ini has no 'ActiveModList=$($info.PackageName)', so the loader will not install it. Enable it under Options -> Mod Management."
    }
    foreach ($dependency in @($info.Dependencies)) {
        if (-not ($settings | Where-Object { $_ -match "^\s*ActiveModList\s*=\s*$([regex]::Escape([string]$dependency))\s*$" })) {
            Write-Warning "Dependency '$dependency' has no 'ActiveModList=$dependency' in PalModSettings.ini, so the loader will not install it. Subscribe to it and enable it under Options -> Mod Management."
        }
    }
}

Write-Host ""
if ($DryRun) {
    Write-Host "Dry run only. Nothing was changed."
}
else {
    if ($stale.Count -gt 0) { Write-Host "Deleted $($stale.Count) file(s) the package no longer has." }
    Write-Host "Staged $($info.PackageName) $newVersion as a $kind (DebugMode $newDebug), and wrote both to the repo's Info.json. Upload it from Palworld Mod Uploader; this machine reinstalls from the item folder at its next launch, a subscribed machine after Steam downloads the upload. Paste .docs\workshop-description.txt into the Workshop page if that file changed."
}
