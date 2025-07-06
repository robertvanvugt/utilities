<#+
.SYNOPSIS
    Generic PowerShell utilities module. Add new utility functions here.
.DESCRIPTION
    This module contains reusable utility functions for file management and other tasks.
#>

function Invoke-SyncFolders {
    <#
    .SYNOPSIS
        Synchronizes files between folders, with delta preview, interactive approval, and efficient hash checking.
    .PARAMETER SourceFolder
        The source folder to sync from.
    .PARAMETER DestinationFolder
        The destination folder to sync to.
    .PARAMETER NoCheckHash
        If specified, disables SHA256 file hash comparison (uses only size/timestamp).
    .PARAMETER HashThreshold
        Maximum file size to check hash (supports '2GB', '500MB', '1000000000'). Larger files only use size/timestamp.
    .EXAMPLE
        Invoke-SyncFolders -SourceFolder C:\Data -DestinationFolder D:\Backup
    .EXAMPLE
        Invoke-SyncFolders -SourceFolder .\A -DestinationFolder .\B -HashThreshold 500MB
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$SourceFolder,

        [Parameter(Mandatory=$true)]
        [string]$DestinationFolder,

        [switch]$NoCheckHash,

        [string]$HashThreshold = "2GB"
    )

    function Convert-SizeStringToBytes {
        param([string]$sizeString)
        if ($sizeString -match '^\s*(\d+(?:\.\d+)?)\s*(B|KB|MB|GB|TB)?\s*$') {
            $num = [double]$matches[1]
            $unit = ($matches[2] -replace '\s','').ToUpper()
            switch ($unit) {
                "TB" { return [int64]($num * 1TB) }
                "GB" { return [int64]($num * 1GB) }
                "MB" { return [int64]($num * 1MB) }
                "KB" { return [int64]($num * 1KB) }
                default { return [int64]$num }
            }
        }
        throw "Invalid size string: $sizeString (try e.g. '2GB', '512MB', '1000000')"
    }

    $CheckHash = -not $NoCheckHash.IsPresent
    $HashThresholdBytes = Convert-SizeStringToBytes $HashThreshold

    function Get-DeltaTable {
        param($fromRoot, $toRoot, $checkHash, $hashThresholdBytes)
        $fromFiles = Get-ChildItem -Path $fromRoot -Recurse -File
        $deltaRows = @()
        foreach ($file in $fromFiles) {
            $relativePath = $file.FullName.Substring($fromRoot.Length).TrimStart('\','/')
            $toFile = Join-Path $toRoot $relativePath
            $copy = $true
            $reason = "File does not exist at destination"
            $srcHash = $null
            $dstHash = $null
            $largeFile = $file.Length -gt $hashThresholdBytes

            if (Test-Path $toFile) {
                $toInfo = Get-Item $toFile

                if ($checkHash -and -not $largeFile -and $toInfo.Length -le $hashThresholdBytes) {
                    $srcHash = (Get-FileHash -Algorithm SHA256 -Path $file.FullName).Hash
                    $dstHash = (Get-FileHash -Algorithm SHA256 -Path $toFile).Hash
                    if ($srcHash -eq $dstHash) {
                        $copy = $false
                    } else {
                        $reason = "File hashes differ"
                    }
                } else {
                    # Large file: use size/timestamp only
                    if ($toInfo.Length -eq $file.Length -and $toInfo.LastWriteTime -eq $file.LastWriteTime) {
                        $copy = $false
                    } else {
                        $reason = "Destination differs (size/timestamp mismatch)"
                    }
                }
            } else {
                if ($checkHash -and -not $largeFile) {
                    $srcHash = (Get-FileHash -Algorithm SHA256 -Path $file.FullName).Hash
                }
            }
            $deltaRows += [PSCustomObject]@{
                "Source File" = $file.FullName
                "Src Size"    = $file.Length
                "Src Time"    = $file.LastWriteTime
                "Src Hash"    = if ($srcHash) { $srcHash.Substring($srcHash.Length - 5) } else { "" }
                "<-->"        = "-->"
                "Dest File"   = $toFile
                "Dst Size"    = if (Test-Path $toFile) { (Get-Item $toFile).Length } else { "" }
                "Dst Time"    = if (Test-Path $toFile) { (Get-Item $toFile).LastWriteTime } else { "" }
                "Dst Hash"    = if ($dstHash) { $dstHash.Substring($dstHash.Length - 5) } else { "" }
                "Reason"      = $reason + ($(if ($largeFile) { " (large file: hash skipped)" } else { "" }))
            }
        }
        return $deltaRows
    }

    function Get-FolderDelta {
        param($fromRoot, $toRoot)
        $fromDirs = Get-ChildItem -Path $fromRoot -Recurse -Directory
        $createdFolders = @()
        foreach ($dir in $fromDirs) {
            $relativePath = $dir.FullName.Substring($fromRoot.Length).TrimStart('\','/')
            $toDir = Join-Path $toRoot $relativePath
            if (-not (Test-Path $toDir -PathType Container)) {
                $createdFolders += $relativePath
            }
        }
        return $createdFolders
    }

    function Invoke-Sync {
        param($deltaRows, $createdFolders, $fromRoot, $toRoot)
        foreach ($folder in $createdFolders) {
            $toDir = Join-Path $toRoot $folder
            if (-not (Test-Path $toDir -PathType Container)) {
                New-Item -ItemType Directory -Path $toDir -Force | Out-Null
                Write-Host "Created folder: $folder" -ForegroundColor Green
            }
        }
        foreach ($row in $deltaRows) {
            $fromFile = $row."Source File"
            $toFile = $row."Dest File"
            $toDir = Split-Path $toFile -Parent
            if (-not (Test-Path $toDir)) {
                New-Item -ItemType Directory -Path $toDir -Force | Out-Null
            }
            Copy-Item -Path $fromFile -Destination $toFile -Force
            Write-Host "Copied: $($fromFile.Substring($fromRoot.Length).TrimStart('\','/'))" -ForegroundColor Green
        }
    }

    # --- Phase 1: Preview and approve source -> destination ---
    $createdFolders = Get-FolderDelta -fromRoot $SourceFolder -toRoot $DestinationFolder
    $deltaRows = Get-DeltaTable -fromRoot $SourceFolder -toRoot $DestinationFolder -checkHash:$CheckHash -hashThresholdBytes:$HashThresholdBytes

    Write-Host "`n========== SYNC PREVIEW: Source --> Destination ==========" -ForegroundColor Cyan
    if ($createdFolders.Count -gt 0) {
        Write-Host "Folders to be created in destination:"
        $createdFolders | ForEach-Object { Write-Host "  $_" -ForegroundColor Cyan }
    }
    if ($deltaRows.Count -gt 0) {
        Write-Host "`nFiles to be copied/overwritten:" -ForegroundColor Cyan
        $deltaRows | Format-Table -AutoSize
        $doForward = Read-Host "`nWould you like to perform this sync from source to destination? [Y/N]"
        if ($doForward -match '^[Yy]$') {
            Invoke-Sync -deltaRows $deltaRows -createdFolders $createdFolders -fromRoot $SourceFolder -toRoot $DestinationFolder
            Write-Host "Forward sync complete." -ForegroundColor Green
        } else {
            Write-Host "No files/folders were copied." -ForegroundColor Yellow
        }
    } else {
        Write-Host "No files to sync (delta table empty)." -ForegroundColor Green
    }

    # --- Phase 2: Preview and approve destination -> source for orphans ---
    function Get-OrphanDeltaTable {
        param($fromRoot, $toRoot, $checkHash, $hashThresholdBytes)
        $fromFiles = Get-ChildItem -Path $fromRoot -Recurse -File
        $deltaRows = @()
        foreach ($file in $fromFiles) {
            $relativePath = $file.FullName.Substring($fromRoot.Length).TrimStart('\','/')
            $toFile = Join-Path $toRoot $relativePath
            if (-not (Test-Path $toFile)) {
                $largeFile = $file.Length -gt $hashThresholdBytes
                $dstHash = $null
                if ($checkHash -and -not $largeFile) {
                    $dstHash = (Get-FileHash -Algorithm SHA256 -Path $file.FullName).Hash
                }
                $deltaRows += [PSCustomObject]@{
                    "Source File" = $toFile
                    "Src Size"    = ""
                    "Src Time"    = ""
                    "Src Hash"    = ""
                    "<-->"        = "<--"
                    "Dest File"   = $file.FullName
                    "Dst Size"    = $file.Length
                    "Dst Time"    = $file.LastWriteTime
                    "Dst Hash"    = if ($dstHash) { $dstHash.Substring($dstHash.Length - 5) } else { "" }
                    "Reason"      = "File does not exist at source" + ($(if ($largeFile) { " (large file: hash skipped)" } else { "" }))
                }
            }
        }
        return $deltaRows
    }
    function Get-OrphanFolderDelta {
        param($fromRoot, $toRoot)
        $fromDirs = Get-ChildItem -Path $fromRoot -Recurse -Directory
        $createdFolders = @()
        foreach ($dir in $fromDirs) {
            $relativePath = $dir.FullName.Substring($fromRoot.Length).TrimStart('\','/')
            $toDir = Join-Path $toRoot $relativePath
            if (-not (Test-Path $toDir -PathType Container)) {
                $createdFolders += $relativePath
            }
        }
        return $createdFolders
    }

    $orphanFolders = Get-OrphanFolderDelta -fromRoot $DestinationFolder -toRoot $SourceFolder
    $orphanRows = Get-OrphanDeltaTable -fromRoot $DestinationFolder -toRoot $SourceFolder -checkHash:$CheckHash -hashThresholdBytes:$HashThresholdBytes

    if ($orphanFolders.Count -gt 0 -or $orphanRows.Count -gt 0) {
        Write-Host "`n========== REVERSE SYNC PREVIEW: Destination <-- Source (Orphans) ==========" -ForegroundColor Magenta
        if ($orphanFolders.Count -gt 0) {
            Write-Host "Folders to be created in source:"
            $orphanFolders | ForEach-Object { Write-Host "  $_" -ForegroundColor Magenta }
        }
        if ($orphanRows.Count -gt 0) {
            Write-Host "`nFiles to be copied back to source:" -ForegroundColor Magenta
            $orphanRows | Format-Table -AutoSize
            $doReverse = Read-Host "`nWould you like to sync these orphans back to the source? [Y/N]"
            if ($doReverse -match '^[Yy]$') {
                $orphanRowsForSync = @()
                foreach ($row in $orphanRows) {
                    $orphanRowsForSync += [PSCustomObject]@{
                        "Source File" = $row."Dest File"
                        "Dest File"   = $row."Source File"
                    }
                }
                Invoke-Sync -deltaRows $orphanRowsForSync -createdFolders $orphanFolders -fromRoot $DestinationFolder -toRoot $SourceFolder
                Write-Host "Reverse sync complete." -ForegroundColor Green
            } else {
                Write-Host "No orphans were synced back." -ForegroundColor Yellow
            }
        } else {
            Write-Host "No orphan files to sync back." -ForegroundColor Green
        }
    } else {
        Write-Host "`nNo orphans found in destination." -ForegroundColor Green
    }
}

Export-ModuleMember -Function Invoke-SyncFolders
