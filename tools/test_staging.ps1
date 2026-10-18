<#
.SYNOPSIS
    End-to-end test of tools\stage.ps1 against throwaway folders.

.DESCRIPTION
    Each case builds, under %TEMP%, a repo with a copy of stage.ps1 in its
    tools\, a Workshop content directory holding an item folder, and a game
    root holding Mods\PalModSettings.ini. It runs the copy in a child pwsh with
    -WorkshopRoot and -GameRoot pointed at those folders, then checks the exit
    code, the output, the repo's Info.json and the item folder. The real game,
    Workshop and uploader folders are never read or written.

    Prints PASS or FAIL per check, then ALL PASS or the failure count; exits 1
    on any failure. The temp folders are deleted at the end unless -Keep.

.PARAMETER Keep
    Leave the temp folders in place and print where they are.

.EXAMPLE
    .\tools\test_staging.ps1
#>
[CmdletBinding()]
param([switch] $Keep)

$ErrorActionPreference = 'Stop'

$STAGE = Join-Path $PSScriptRoot 'stage.ps1'
$PWSH = (Get-Process -Id $PID).Path
$TEMP_ROOT = Join-Path ([System.IO.Path]::GetTempPath()) ("test_staging_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$script:failures = 0

#-------------------------------------------------------------------------------
# Fixture helpers
#-------------------------------------------------------------------------------

# A package manifest as a hashtable: PackageName TestMod, Version 1.2.0,
# DebugMode false, one Dependency, and a client and a server Lua rule on
# ./Scripts.
function New-Info {
    return [ordered]@{
        ModName      = 'Test Mod'
        PackageName  = 'TestMod'
        Version      = '1.2.0'
        DebugMode    = $false
        MinRevision  = 1
        Author       = 'test'
        Thumbnail    = 'thumbnail.png'
        Dependencies = @('Dep1')
        Tags         = @('Gameplay')
        InstallRule  = @(
            [ordered]@{ Type = 'Lua'; Targets = @('./Scripts') }
            [ordered]@{ Type = 'Lua'; IsServer = $true; Targets = @('./Scripts') }
        )
    }
}

# Writes $Content to $Path, creating its directory.
function Write-File {
    param([string] $Path, [string] $Content)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding $false))
}

# Builds a repo, a Workshop root with $ItemFolders item folders, and a game
# root, all under a fresh folder in $TEMP_ROOT. Returns their paths; Item is
# the first item folder.
function New-Fixture {
    param(
        $Info = (New-Info),
        [string] $InfoText,
        [string[]] $RepoFiles = @('Scripts\main.lua'),
        [string[]] $ItemFiles = @(),
        [string[]] $Active = @('TestMod', 'Dep1'),
        [int] $ItemFolders = 1,
        [string] $ItemPackage = 'TestMod'
    )
    $root = Join-Path $TEMP_ROOT ([guid]::NewGuid().ToString('N').Substring(0, 8))
    $repo = Join-Path $root 'repo'
    $workshop = Join-Path $root 'workshop'
    $game = Join-Path $root 'game'

    New-Item -ItemType Directory -Force -Path (Join-Path $repo 'tools'), $workshop, (Join-Path $game 'Mods') | Out-Null
    Copy-Item -LiteralPath $STAGE -Destination (Join-Path $repo 'tools\stage.ps1')

    if (-not $InfoText) { $InfoText = $Info | ConvertTo-Json -Depth 6 }
    Write-File (Join-Path $repo 'Info.json') $InfoText
    foreach ($file in @('thumbnail.png', 'LICENSE', 'README.md') + $RepoFiles) {
        Write-File (Join-Path $repo $file) "repo $file"
    }

    for ($i = 1; $i -le $ItemFolders; $i++) {
        $item = Join-Path $workshop "100$i"
        Write-File (Join-Path $item 'Info.json') (@{ PackageName = $ItemPackage; Version = '1.0.0'; DebugMode = $false } | ConvertTo-Json)
        Write-File (Join-Path $item '.workshop.json') '{"publishedfileid":"1001","changenote":null,"last_published_version":"0.0.1"}'
    }
    foreach ($file in $ItemFiles) {
        Write-File (Join-Path $workshop "1001\$file") "item $file"
    }

    $settings = @('[PalModSettings]', 'bGlobalEnableMod=True', "WorkshopRootDir=$workshop") +
    @($Active | ForEach-Object { "ActiveModList=$_" })
    Write-File (Join-Path $game 'Mods\PalModSettings.ini') ($settings -join "`r`n")

    return [pscustomobject]@{
        Repo     = $repo
        Workshop = $workshop
        Game     = $game
        Item     = Join-Path $workshop '1001'
    }
}

# Runs the fixture's copy of stage.ps1 in a child pwsh with $Arguments. Returns
# its exit code and its combined output as one string.
function Invoke-Stage {
    param($Fixture, [string[]] $Arguments = @())
    $out = & $PWSH -NoProfile -NonInteractive -File (Join-Path $Fixture.Repo 'tools\stage.ps1') `
        -WorkshopRoot $Fixture.Workshop -GameRoot $Fixture.Game @Arguments 2>&1 | Out-String
    return [pscustomobject]@{ Exit = $LASTEXITCODE; Out = $out }
}

# The fixture repo's Info.json, parsed.
function Get-RepoInfo {
    param($Fixture)
    return Get-Content -Raw (Join-Path $Fixture.Repo 'Info.json') | ConvertFrom-Json
}

# A hash of every file under $Root, keyed by relative path, for before/after
# comparison.
function Get-Snapshot {
    param([string] $Root)
    $prefix = (Resolve-Path -LiteralPath $Root).Path.TrimEnd('\') + '\'
    $snapshot = @{}
    Get-ChildItem -LiteralPath $Root -Recurse -File -Force | ForEach-Object {
        $snapshot[$_.FullName.Substring($prefix.Length)] = (Get-FileHash -LiteralPath $_.FullName).Hash
    }
    return ($snapshot.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join "`n"
}

# Records one check: prints PASS or FAIL, and on FAIL the run's output.
function Test-That {
    param([string] $Name, [bool] $Condition, $Run)
    if ($Condition) {
        Write-Host "PASS  $Name"
    }
    else {
        Write-Host "FAIL  $Name"
        if ($Run) { Write-Host ($Run.Out -replace '(?m)^', '        ') }
        $script:failures++
    }
}

#-------------------------------------------------------------------------------
# Cases
#-------------------------------------------------------------------------------

try {
    # Dev build: patch + 1, DebugMode true, written to the repo and staged.
    $fx = New-Fixture
    $workshopBefore = Get-Content -Raw (Join-Path $fx.Item '.workshop.json')
    $run = Invoke-Stage $fx
    $info = Get-RepoInfo $fx
    Test-That 'dev stage exits 0' ($run.Exit -eq 0) $run
    Test-That 'dev stage writes Version 1.2.1 to the repo' ($info.Version -eq '1.2.1') $run
    Test-That 'dev stage writes DebugMode true to the repo' ($info.DebugMode -eq $true) $run
    Test-That 'staged Info.json is the repo Info.json byte for byte' (
        (Get-FileHash (Join-Path $fx.Repo 'Info.json')).Hash -eq (Get-FileHash (Join-Path $fx.Item 'Info.json')).Hash) $run
    Test-That 'Targets folder is staged' (Test-Path (Join-Path $fx.Item 'Scripts\main.lua')) $run
    Test-That 'Thumbnail and LICENSE are staged' ((Test-Path (Join-Path $fx.Item 'thumbnail.png')) -and (Test-Path (Join-Path $fx.Item 'LICENSE'))) $run
    Test-That 'README and tools are not staged' (-not (Test-Path (Join-Path $fx.Item 'README.md')) -and -not (Test-Path (Join-Path $fx.Item 'tools'))) $run
    Test-That '.workshop.json is untouched' ((Get-Content -Raw (Join-Path $fx.Item '.workshop.json')) -eq $workshopBefore) $run
    Test-That 'a target named by a client and a server rule is staged once' (([regex]::Matches($run.Out, 'stage  Scripts')).Count -eq 1) $run

    # Release: minor + 1, patch 0, DebugMode false.
    $run = Invoke-Stage $fx @('-Publish')
    $info = Get-RepoInfo $fx
    Test-That 'publish exits 0' ($run.Exit -eq 0) $run
    Test-That 'publish writes Version 1.3.0' ($info.Version -eq '1.3.0') $run
    Test-That 'publish writes DebugMode false' ($info.DebugMode -eq $false) $run

    # Patch numbers count, they do not concatenate.
    $infoTable = New-Info; $infoTable.Version = '1.0.9'
    $fx = New-Fixture -Info $infoTable
    $run = Invoke-Stage $fx
    Test-That 'patch 9 increments to 10' ((Get-RepoInfo $fx).Version -eq '1.0.10') $run

    # -DryRun writes nothing anywhere.
    $fx = New-Fixture
    $repoBefore = Get-Snapshot $fx.Repo
    $itemBefore = Get-Snapshot $fx.Item
    $run = Invoke-Stage $fx @('-DryRun')
    Test-That '-DryRun exits 0' ($run.Exit -eq 0) $run
    Test-That '-DryRun prints the next version' ($run.Out -match '1\.2\.0 -> 1\.2\.1') $run
    Test-That '-DryRun leaves the repo unchanged' ((Get-Snapshot $fx.Repo) -eq $repoBefore) $run
    Test-That '-DryRun leaves the item folder unchanged' ((Get-Snapshot $fx.Item) -eq $itemBefore) $run

    # A stale file in the item folder stops the run before anything is written.
    $fx = New-Fixture -ItemFiles @('Scripts\old.lua')
    $repoBefore = Get-Snapshot $fx.Repo
    $itemBefore = Get-Snapshot $fx.Item
    $run = Invoke-Stage $fx
    Test-That 'stale file stops the stage with exit 1' ($run.Exit -eq 1) $run
    Test-That 'stale stop names the file' ($run.Out -match 'Scripts\\old\.lua') $run
    Test-That 'stale stop leaves the repo Info.json unbumped' ((Get-Snapshot $fx.Repo) -eq $repoBefore) $run
    Test-That 'stale stop leaves the item folder unchanged' ((Get-Snapshot $fx.Item) -eq $itemBefore) $run
    $run = Invoke-Stage $fx @('-DryRun')
    Test-That 'stale stop under -DryRun exits 0' ($run.Exit -eq 0) $run
    $run = Invoke-Stage $fx @('-Force')
    Test-That '-Force exits 0' ($run.Exit -eq 0) $run
    Test-That '-Force deletes the stale file' (-not (Test-Path (Join-Path $fx.Item 'Scripts\old.lua'))) $run

    # -Publish deletes stale files without -Force, and a directory left empty.
    $fx = New-Fixture -ItemFiles @('Scripts\old.lua', 'Retired\gone.json')
    $run = Invoke-Stage $fx @('-Publish', '-DryRun')
    Test-That 'stale publish under -DryRun exits 0' ($run.Exit -eq 0) $run
    Test-That 'stale publish under -DryRun keeps the stale file' (Test-Path (Join-Path $fx.Item 'Scripts\old.lua')) $run
    $run = Invoke-Stage $fx @('-Publish')
    Test-That 'stale publish exits 0' ($run.Exit -eq 0) $run
    Test-That 'publish deletes the stale file' (-not (Test-Path (Join-Path $fx.Item 'Scripts\old.lua'))) $run
    Test-That 'publish removes a directory left empty' (-not (Test-Path (Join-Path $fx.Item 'Retired'))) $run
    Test-That 'stale publish writes a release version' ((Get-RepoInfo $fx).Version -eq '1.3.0') $run

    # A first stage into a Create New Mod folder: the template's main.lua is
    # overwritten and its empty type folders are removed.
    $fx = New-Fixture -ItemFiles @('Scripts\main.lua')
    New-Item -ItemType Directory -Force -Path (Join-Path $fx.Item 'Paks'), (Join-Path $fx.Item 'LogicMods') | Out-Null
    $run = Invoke-Stage $fx
    Test-That 'first stage over the template exits 0' ($run.Exit -eq 0) $run
    Test-That 'template main.lua is replaced by the repo one' ((Get-Content -Raw (Join-Path $fx.Item 'Scripts\main.lua')) -eq 'repo Scripts\main.lua') $run
    Test-That 'empty template folders are removed' (-not (Test-Path (Join-Path $fx.Item 'Paks')) -and -not (Test-Path (Join-Path $fx.Item 'LogicMods'))) $run

    # Info.json checks: each stops the run with exit 1 and writes nothing.
    $badCases = @(
        @{ Name = 'Version not <major>.<minor>.<patch>'; Edit = { param($i) $i.Version = '1.2' } }
        @{ Name = 'DebugMode missing'; Edit = { param($i) $i.Remove('DebugMode') } }
        @{ Name = 'PackageName not alphanumeric'; Edit = { param($i) $i.PackageName = 'Test-Mod' } }
        @{ Name = 'undefined Tag'; Edit = { param($i) $i.Tags = @('Cheats') } }
        @{ Name = 'undefined InstallRule Type'; Edit = { param($i) $i.InstallRule[0].Type = 'Blueprint' } }
        @{ Name = "Targets '.'"; Edit = { param($i) $i.InstallRule[0].Targets = @('.') } }
        @{ Name = 'Targets outside the repo'; Edit = { param($i) $i.InstallRule[0].Targets = @('../elsewhere') } }
        @{ Name = 'Thumbnail missing from the repo'; Edit = { param($i) $i.Thumbnail = 'missing.png' } }
        @{ Name = 'PalSchema folder target named after the package'; Edit = { param($i) $i.InstallRule += [ordered]@{ Type = 'PalSchema'; Targets = @('./Data/TestMod') } } }
    )
    foreach ($case in $badCases) {
        $infoTable = New-Info
        & $case.Edit $infoTable
        $package = if ($infoTable.PackageName -eq 'Test-Mod') { 'Test-Mod' } else { 'TestMod' }
        $fx = New-Fixture -Info $infoTable -RepoFiles @('Scripts\main.lua', 'Data\TestMod\raw\a.json') -ItemPackage $package
        $repoBefore = Get-Snapshot $fx.Repo
        $run = Invoke-Stage $fx
        Test-That "refuses: $($case.Name)" ($run.Exit -eq 1 -and (Get-Snapshot $fx.Repo) -eq $repoBefore) $run
    }

    # The same package-named folder with a trailing slash copies its contents,
    # so it is accepted and staged.
    $infoTable = New-Info
    $infoTable.InstallRule += [ordered]@{ Type = 'PalSchema'; Targets = @('./Data/TestMod/') }
    $fx = New-Fixture -Info $infoTable -RepoFiles @('Scripts\main.lua', 'Data\TestMod\raw\a.json')
    $run = Invoke-Stage $fx
    Test-That 'package-named folder with a trailing slash is accepted' ($run.Exit -eq 0) $run
    Test-That 'trailing-slash target is staged' (Test-Path (Join-Path $fx.Item 'Data\TestMod\raw\a.json')) $run
    Test-That 'trailing-slash target prints as contents' ($run.Out -match "contents of './Data/TestMod/'") $run

    # A Targets path missing from the repo is warned about and skipped.
    $infoTable = New-Info
    $infoTable.InstallRule += [ordered]@{ Type = 'Paks'; Targets = @('./Paks/') }
    $fx = New-Fixture -Info $infoTable
    $run = Invoke-Stage $fx
    Test-That 'missing target still stages, exit 0' ($run.Exit -eq 0) $run
    Test-That 'missing target is warned about' ($run.Out -match "Targets './Paks/' does not exist") $run

    # Item folder detection.
    $fx = New-Fixture -ItemFolders 2
    $run = Invoke-Stage $fx
    Test-That 'two folders with the PackageName stop the run' ($run.Exit -eq 1 -and $run.Out -match '2 folders') $run
    $fx = New-Fixture -ItemPackage 'MyAwesomeMod'
    $run = Invoke-Stage $fx
    Test-That 'no folder with the PackageName stops the run' ($run.Exit -ne 0 -and $run.Out -match 'MyAwesomeMod') $run

    # PalModSettings.ini warnings.
    $fx = New-Fixture -Active @('TestMod')
    $run = Invoke-Stage $fx
    Test-That 'a Dependency not in ActiveModList is warned about' ($run.Exit -eq 0 -and $run.Out -match "Dependency 'Dep1'") $run
    $fx = New-Fixture -Active @('Dep1')
    $run = Invoke-Stage $fx
    Test-That 'the package not in ActiveModList is warned about' ($run.Out -match "no 'ActiveModList=TestMod'") $run
    $fx = New-Fixture
    $run = Invoke-Stage $fx
    Test-That 'no settings warning when everything is enabled' ($run.Out -notmatch 'ActiveModList') $run
}
finally {
    if ($Keep) {
        Write-Host ""
        Write-Host "Temp folders kept at $TEMP_ROOT"
    }
    elseif (Test-Path $TEMP_ROOT) {
        Remove-Item -LiteralPath $TEMP_ROOT -Recurse -Force
    }
}

Write-Host ""
if ($script:failures -eq 0) {
    Write-Host "ALL PASS"
    exit 0
}
Write-Host "$($script:failures) FAILED"
exit 1
