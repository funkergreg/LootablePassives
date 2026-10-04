<#
.SYNOPSIS
    The mirror rule shared by install.ps1 and stage.ps1. Dot-sourced; not run on
    its own.

.DESCRIPTION
    Get-RelativePaths       paths under a root, relative to that root
    Stop-OnStale            lists stale files and ends the calling script
    Remove-EmptyDirectories deletes directories left holding nothing
#>

# Paths of every file under $Root, relative to $Root, or @() when $Root is
# absent. -IncludeDirectories adds every directory under it as well.
function Get-RelativePaths {
    param(
        [string] $Root,
        [switch] $IncludeDirectories
    )
    if (-not (Test-Path $Root)) { return @() }
    $prefix = (Resolve-Path -LiteralPath $Root).Path.TrimEnd('\') + '\'
    $items = if ($IncludeDirectories) {
        Get-ChildItem -LiteralPath $Root -Recurse -Force
    }
    else {
        Get-ChildItem -LiteralPath $Root -Recurse -File -Force
    }
    return @($items | ForEach-Object { $_.FullName.Substring($prefix.Length) })
}

# Prints $Heading as a warning, one line per entry of $Listing, then $Message,
# and ends the calling script: exit 0 under -DryRun, exit 1 otherwise. Nothing
# has been changed at the point a caller reaches this.
function Stop-OnStale {
    param(
        [string] $Heading,
        [string[]] $Listing,
        [string] $Message,
        [switch] $DryRun
    )
    Write-Host ""
    Write-Warning $Heading
    foreach ($line in $Listing) { Write-Host "    $line" }
    Write-Host ""
    Write-Host $Message
    if ($DryRun) {
        Write-Host ""
        Write-Host "Dry run only. Nothing was changed."
        exit 0
    }
    exit 1
}

# Deletes directories under $Root that hold nothing, deepest first, so that a
# folder emptied by the stale sweep does not survive as an empty shell. Under
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
