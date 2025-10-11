<#+
.SYNOPSIS
    Generic PowerShell utilities module. Add new utility functions here.
.DESCRIPTION
    This module contains reusable utility functions for file management and other tasks.
#>

function Invoke-SyncFolders {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$SourceFolder,

        [Parameter(Mandatory = $true)]
        [string]$DestinationFolder,

        [switch]$NoCheckHash,

        [string]$HashThreshold = "2GB",

        [string[]]$IncludeExtensions = @(),

        [string[]]$ExcludeExtensions = @()
    )

    <#
    .SYNOPSIS
        Converts a size string (e.g., 2GB, 500MB) to bytes.
    #>
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

    <#
    .SYNOPSIS
        Filters a collection of files by include/exclude extension (case-insensitive).
    #>
    function Filter-FilesByExtension {
        param(
            [Parameter(Mandatory = $true)] $files,
            [string[]]$include = @(),
            [string[]]$exclude = @()
        )
        # Normalize extensions for case-insensitive match
        $inc = $include | ForEach-Object { $_.ToLowerInvariant() }
        $exc = $exclude | ForEach-Object { $_.ToLowerInvariant() }
        $filtered = $files
        if ($inc.Count -gt 0) {
            $filtered = $filtered | Where-Object { $inc -contains $_.Extension.ToLowerInvariant() }
        }
        if ($exc.Count -gt 0) {
            $filtered = $filtered | Where-Object { $exc -notcontains $_.Extension.ToLowerInvariant() }
        }
        return $filtered
    }

    $CheckHash = -not $NoCheckHash.IsPresent
    $HashThresholdBytes = Convert-SizeStringToBytes $HashThreshold

    # --- Summary Counters ---
    $Summary = @{
        ForwardFolders = 0
        ForwardFiles   = 0
        ReverseFolders = 0
        ReverseFiles   = 0
    }

    function Get-DeltaTable {
        param(
            $fromRoot, $toRoot, $checkHash, $hashThresholdBytes,
            [string[]]$IncludeExtensions = @(), [string[]]$ExcludeExtensions = @()
        )
        $fromFiles = Get-ChildItem -Path $fromRoot -Recurse -File
        $fromFiles = Filter-FilesByExtension $fromFiles $IncludeExtensions $ExcludeExtensions
        $deltaRows = @()
        foreach ($file in $fromFiles) {
            $relativePath = $file.FullName.Substring($fromRoot.Length).TrimStart('\','/')
            $toFile = Join-Path $toRoot $relativePath
            $toExists = Test-Path $toFile
            $toSize = $toExists ? (Get-Item $toFile).Length : ""
            $toTime = $toExists ? (Get-Item $toFile).LastWriteTime : ""
            $srcHash = ""
            $dstHash = ""
            $largeFile = $file.Length -gt $hashThresholdBytes
            $differs = $false
            $reason = ""

            if (-not $toExists) {
                $reason = "File does not exist at destination"
                if ($checkHash -and -not $largeFile) {
                    $srcHash = (Get-FileHash -Algorithm SHA256 -Path $file.FullName).Hash
                }
                $deltaRows += [PSCustomObject]@{
                    "Source File" = $file.FullName
                    "Src Size"    = $file.Length
                    "Src Time"    = $file.LastWriteTime
                    "Src Hash"    = if ($checkHash -and $srcHash) { $srcHash.Substring($srcHash.Length - 5) } else { "" }
                    "<-->"        = "-->"
                    "Dest File"   = $toFile
                    "Dst Size"    = ""
                    "Dst Time"    = ""
                    "Dst Hash"    = ""
                    "Reason"      = $reason + ($(if ($checkHash -and $largeFile) { " (large file: hash skipped)" } else { "" }))
                    "DupType"     = "copy"
                }
            } else {
                if ($checkHash -and -not $largeFile) {
                    $srcHash = (Get-FileHash -Algorithm SHA256 -Path $file.FullName).Hash
                    $dstHash = (Get-FileHash -Algorithm SHA256 -Path $toFile).Hash
                    $differs = $srcHash -ne $dstHash
                    $reason = $differs ? "File hashes differ" : ""
                } elseif ($checkHash -and $largeFile) {
                    $differs = ($toSize -ne $file.Length) -or ($toTime -ne $file.LastWriteTime)
                    $reason = $differs ? "Size/timestamp differ (large file: hash skipped)" : ""
                } else {
                    $differs = ($toSize -ne $file.Length) -or ($toTime -ne $file.LastWriteTime)
                    $reason = $differs ? "Size/timestamp differ" : ""
                }
                if ($differs) {
                    $deltaRows += [PSCustomObject]@{
                        "Source File" = $file.FullName
                        "Src Size"    = $file.Length
                        "Src Time"    = $file.LastWriteTime
                        "Src Hash"    = if ($checkHash -and $srcHash) { $srcHash.Substring($srcHash.Length - 5) } else { "" }
                        "<-->"        = "-->"
                        "Dest File"   = $toFile
                        "Dst Size"    = $toSize
                        "Dst Time"    = $toTime
                        "Dst Hash"    = if ($checkHash -and $dstHash) { $dstHash.Substring($dstHash.Length - 5) } else { "" }
                        "Reason"      = $reason
                        "DupType"     = "conflict"
                    }
                }
            }
        }
        return $deltaRows
    }

    function Get-ReverseDeltaTable {
        param(
            $fromRoot, $toRoot, $checkHash, $hashThresholdBytes,
            [string[]]$IncludeExtensions = @(), [string[]]$ExcludeExtensions = @()
        )
        $fromFiles = Get-ChildItem -Path $fromRoot -Recurse -File
        $fromFiles = Filter-FilesByExtension $fromFiles $IncludeExtensions $ExcludeExtensions
        $deltaRows = @()
        foreach ($file in $fromFiles) {
            $relativePath = $file.FullName.Substring($fromRoot.Length).TrimStart('\','/')
            $toFile = Join-Path $toRoot $relativePath
            $srcExists = Test-Path $toFile
            $srcSize = $srcExists ? (Get-Item $toFile).Length : ""
            $srcTime = $srcExists ? (Get-Item $toFile).LastWriteTime : ""
            $srcHash = ""
            $dstHash = ""
            $largeFile = $file.Length -gt $hashThresholdBytes
            $differs = $false
            $reason = ""

            if (-not $srcExists) {
                $reason = "File does not exist at source"
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
                    "Dst Hash"    = if ($checkHash -and $dstHash) { $dstHash.Substring($dstHash.Length - 5) } else { "" }
                    "Reason"      = $reason + ($(if ($checkHash -and $largeFile) { " (large file: hash skipped)" } else { "" }))
                    "DupType"     = "copy"
                }
            } else {
                if ($checkHash -and -not $largeFile) {
                    $srcHash = (Get-FileHash -Algorithm SHA256 -Path $toFile).Hash
                    $dstHash = (Get-FileHash -Algorithm SHA256 -Path $file.FullName).Hash
                    $differs = $srcHash -ne $dstHash
                    $reason = $differs ? "File hashes differ" : ""
                } elseif ($checkHash -and $largeFile) {
                    $differs = ($srcSize -ne $file.Length) -or ($srcTime -ne $file.LastWriteTime)
                    $reason = $differs ? "Size/timestamp differ (large file: hash skipped)" : ""
                } else {
                    $differs = ($srcSize -ne $file.Length) -or ($srcTime -ne $file.LastWriteTime)
                    $reason = $differs ? "Size/timestamp differ" : ""
                }
                if ($differs) {
                    $deltaRows += [PSCustomObject]@{
                        "Source File" = $toFile
                        "Src Size"    = $srcSize
                        "Src Time"    = $srcTime
                        "Src Hash"    = if ($checkHash -and $srcHash) { $srcHash.Substring($srcHash.Length - 5) } else { "" }
                        "<-->"        = "<--"
                        "Dest File"   = $file.FullName
                        "Dst Size"    = $file.Length
                        "Dst Time"    = $file.LastWriteTime
                        "Dst Hash"    = if ($checkHash -and $dstHash) { $dstHash.Substring($dstHash.Length - 5) } else { "" }
                        "Reason"      = $reason
                        "DupType"     = "conflict"
                    }
                }
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
        param(
            $deltaRows, $createdFolders, $fromRoot, $toRoot, $mode = "forward", $action = "duplicate"
        )
        $foldersCreated = 0
        $filesCopied = 0
        foreach ($folder in $createdFolders) {
            $toDir = Join-Path $toRoot $folder
            if (-not (Test-Path $toDir -PathType Container)) {
                New-Item -ItemType Directory -Path $toDir -Force | Out-Null
                Write-Host "Created folder: $folder" -ForegroundColor Green
                $foldersCreated++
            }
        }
        foreach ($row in $deltaRows) {
            $fromFile = $mode -eq "forward" ? $row."Source File" : $row."Dest File"
            $toFile   = $mode -eq "forward" ? $row."Dest File"   : $row."Source File"
            $toDir = Split-Path $toFile -Parent
            if (-not (Test-Path $toDir)) {
                New-Item -ItemType Directory -Path $toDir -Force | Out-Null
            }
            if ($row.DupType -eq "conflict") {
                if ($action -eq "overwrite" -and $mode -eq "forward") {
                    Copy-Item -Path $fromFile -Destination $toFile -Force
                    Write-Host "Overwrote: $($toFile.Substring($toRoot.Length).TrimStart('\','/'))" -ForegroundColor Red
                    $filesCopied++
                } elseif ($action -eq "duplicate") {
                    $base = [System.IO.Path]::GetFileNameWithoutExtension($toFile)
                    $ext = [System.IO.Path]::GetExtension($toFile)
                    $dupName = "$base-duplicate$ext"
                    $dupPath = Join-Path -Path $toDir -ChildPath $dupName
                    $suffix = 1
                    while (Test-Path $dupPath) {
                        $dupName = "$base-duplicate$suffix$ext"
                        $dupPath = Join-Path -Path $toDir -ChildPath $dupName
                        $suffix++
                    }
                    Copy-Item -Path $fromFile -Destination $dupPath -Force
                    Write-Host "Duplicated as: $($dupPath.Substring($toRoot.Length).TrimStart('\','/'))" -ForegroundColor Yellow
                    $filesCopied++
                }
            } elseif ($row.DupType -eq "copy") {
                if ($action -eq "copy") {
                    if (-not (Test-Path $toFile)) {
                        Copy-Item -Path $fromFile -Destination $toFile
                        Write-Host "Copied (new): $($toFile.Substring($toRoot.Length).TrimStart('\','/'))" -ForegroundColor Green
                        $filesCopied++
                    }
                } elseif ($action -eq "overwrite" -and $mode -eq "forward") {
                    Copy-Item -Path $fromFile -Destination $toFile -Force
                    Write-Host "Copied (overwritten): $($toFile.Substring($toRoot.Length).TrimStart('\','/'))" -ForegroundColor Red
                    $filesCopied++
                } elseif ($action -eq "duplicate") {
                    $base = [System.IO.Path]::GetFileNameWithoutExtension($toFile)
                    $ext = [System.IO.Path]::GetExtension($toFile)
                    $dupName = "$base-duplicate$ext"
                    $dupPath = Join-Path -Path $toDir -ChildPath $dupName
                    $suffix = 1
                    while (Test-Path $dupPath) {
                        $dupName = "$base-duplicate$suffix$ext"
                        $dupPath = Join-Path -Path $toDir -ChildPath $dupName
                        $suffix++
                    }
                    Copy-Item -Path $fromFile -Destination $dupPath -Force
                    Write-Host "Duplicated as: $($dupPath.Substring($toRoot.Length).TrimStart('\','/'))" -ForegroundColor Yellow
                    $filesCopied++
                }
            }
        }
        return @{Folders=$foldersCreated; Files=$filesCopied}
    }

    # --- Phase 1: Preview and approve source --> destination ---
    $createdFolders = Get-FolderDelta -fromRoot $SourceFolder -toRoot $DestinationFolder
    $deltaRows = Get-DeltaTable -fromRoot $SourceFolder -toRoot $DestinationFolder -checkHash:$CheckHash -hashThresholdBytes:$HashThresholdBytes -IncludeExtensions $IncludeExtensions -ExcludeExtensions $ExcludeExtensions

    Write-Host "`n========== SYNC PREVIEW: Source --> Destination ==========" -ForegroundColor Cyan
    if ($createdFolders.Count -gt 0) {
        Write-Host "Folders to be created in destination:"
        $createdFolders | ForEach-Object { Write-Host "  $_" -ForegroundColor Cyan }
    }
    if ($deltaRows.Count -gt 0) {
        Write-Host "`nFiles to be copied/overwritten/duplicated:" -ForegroundColor Cyan
        $deltaRows | Format-Table -AutoSize
        $action = ""
        while ($action -notmatch '^[CODScods]$') {
            $action = Read-Host "`nChoose action: [C]opy all (only new), [O]verwrite all, [D]uplicate all, or [S]kip all"
        }
        switch ($action.ToUpper()) {
            "C" { $selected = "copy" }
            "O" { $selected = "overwrite" }
            "D" { $selected = "duplicate" }
            "S" { $selected = "skip" }
        }
        if ($selected -ne "skip") {
            $result = Invoke-Sync -deltaRows $deltaRows -createdFolders $createdFolders -fromRoot $SourceFolder -toRoot $DestinationFolder -mode "forward" -action $selected
            $Summary.ForwardFolders += $result.Folders
            $Summary.ForwardFiles   += $result.Files
            Write-Host "Forward sync complete." -ForegroundColor Green
        } else {
            Write-Host "No files/folders were copied." -ForegroundColor Yellow
        }
    } else {
        Write-Host "No files to sync (delta table empty)." -ForegroundColor Green
    }

    # --- Phase 2: Preview and approve destination --> source for orphans/diffs ---
    $orphanFolders = Get-FolderDelta -fromRoot $DestinationFolder -toRoot $SourceFolder
    $orphanRows = Get-ReverseDeltaTable -fromRoot $DestinationFolder -toRoot $SourceFolder -checkHash:$CheckHash -hashThresholdBytes:$HashThresholdBytes -IncludeExtensions $IncludeExtensions -ExcludeExtensions $ExcludeExtensions

    if ($orphanFolders.Count -gt 0 -or $orphanRows.Count -gt 0) {
        Write-Host "`n========== REVERSE SYNC PREVIEW: Destination <-- Source (Orphans and Diffs) ==========" -ForegroundColor Magenta
        if ($orphanFolders.Count -gt 0) {
            Write-Host "Folders to be created in source:"
            $orphanFolders | ForEach-Object { Write-Host "  $_" -ForegroundColor Magenta }
        }
        if ($orphanRows.Count -gt 0) {
            Write-Host "`nFiles to be copied/duplicated back to source:" -ForegroundColor Magenta
            $orphanRows | Format-Table -AutoSize
            $action = ""
            while ($action -notmatch '^[CDScds]$') {
                $action = Read-Host "`nChoose action: [C]opy all (only new), [D]uplicate all, or [S]kip all (never overwrite source)"
            }
            switch ($action.ToUpper()) {
                "C" { $selected = "copy" }
                "D" { $selected = "duplicate" }
                "S" { $selected = "skip" }
            }
            if ($selected -ne "skip") {
                $result = Invoke-Sync -deltaRows $orphanRows -createdFolders $orphanFolders -fromRoot $DestinationFolder -toRoot $SourceFolder -mode "reverse" -action $selected
                $Summary.ReverseFolders += $result.Folders
                $Summary.ReverseFiles   += $result.Files
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

    # --- Final summary ---
    Write-Host ""
    Write-Host "==================== SYNC SUMMARY ====================" -ForegroundColor White
    Write-Host "Source --> Destination:" -ForegroundColor Cyan
    Write-Host ("  Folders created: {0,-6} Files copied/overwritten/duplicated: {1,-6}" -f $Summary.ForwardFolders, $Summary.ForwardFiles)
    Write-Host "Destination --> Source:" -ForegroundColor Magenta
    Write-Host ("  Folders created: {0,-6} Files copied/duplicated:           {1,-6}" -f $Summary.ReverseFolders, $Summary.ReverseFiles)
    Write-Host "======================================================" -ForegroundColor White
}

function Group-iPhoneMedia {
    <#
    .SYNOPSIS
        Sort iPhone media in a folder into subfolders: LivePhotos, Pictures, Videos (top-level only).

    .DESCRIPTION
        - Uses ExifTool to detect Live Photo MOVs (Keys:LivePhotoAuto == 1) and moves them to 'LivePhotos'.
        - Moves all regular pictures to 'Pictures'.
        - Moves regular videos to 'Videos', excluding Live Photo MOVs already moved.
        - Non-recursive: only processes files directly under the specified Path.
        - Supports -WhatIf and -Verbose. Avoids overwriting by auto-incrementing file names.

    .PARAMETER Path
        Folder containing your downloaded media (top-level only). Default: current directory.

    .PARAMETER ExifToolPath
        Path or command name for exiftool. Default: 'exiftool.exe'.

    .PARAMETER PictureExtensions
        Picture extensions (no dot). Default includes jpg,jpeg,heic,heif,png,tif,tiff,dng,bmp,gif.

    .PARAMETER VideoExtensions
        Video extensions (no dot). Default includes mov,mp4,m4v,avi,mts,m2ts.
        (Live Photo MOVs are excluded from this set by detection.)
    #>

    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Position=0)]
        [string]$Path = ".",
        [string]$ExifToolPath = "exiftool.exe",
        [string[]]$PictureExtensions = @('jpg','jpeg','heic','heif','png','tif','tiff','dng','bmp','gif'),
        [string[]]$VideoExtensions   = @('mov','mp4','m4v','avi','mts','m2ts')
    )

    # Resolve and validate
    $Path = (Resolve-Path -LiteralPath $Path).Path
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Path not found or not a folder: $Path"
    }

    # Ensure exiftool exists
    try {
        $null = Get-Command -Name $ExifToolPath -ErrorAction Stop
    } catch {
        throw "ExifTool not found: '$ExifToolPath'. Add it to PATH or pass -ExifToolPath."
    }

    # Get top-level files only
    $allFiles = Get-ChildItem -LiteralPath $Path -File

    if (-not $allFiles) {
        Write-Host "No files found in: $Path"
        return
    }

    # 1) Detect Live Photo MOVs (no recursion)
    $exifArgs = @(
        "-m",                        # ignore minor warnings
        "-ext","mov",
        "-if",'$Keys:LivePhotoAuto eq 1',
        "-p",'$FilePath',
        $Path
    )
    Write-Verbose "Running: $ExifToolPath $($exifArgs -join ' ')"
    $livePhotoMovPaths = (& $ExifToolPath @exifArgs) | Where-Object {
        $_ -and (Test-Path -LiteralPath $_ -PathType Leaf)
    }

    # Normalize to hashset (case-insensitive) for fast membership checks
    $livePhotoSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($p in $livePhotoMovPaths) { $null = $livePhotoSet.Add((Resolve-Path -LiteralPath $p).Path) }

    # Partition files by type
    $pictures = @()
    $videos   = @()
    $liveMovs = @()

    foreach ($f in $allFiles) {
        $ext = $f.Extension.TrimStart('.').ToLowerInvariant()
        $full = $f.FullName

        if ($ext -in $PictureExtensions) {
            $pictures += $f
        }
        elseif ($ext -in $VideoExtensions) {
            # If it's a detected Live Photo MOV, classify as liveMovs; else as regular video
            if ($ext -eq 'mov' -and $livePhotoSet.Contains($full)) {
                $liveMovs += $f
            } else {
                $videos += $f
            }
        }
        # else: ignore non-media files silently
    }

    # Prepare destination folders
    $destLive     = Join-Path $Path 'LivePhotos'
    $destPictures = Join-Path $Path 'Pictures'
    $destVideos   = Join-Path $Path 'Videos'

    foreach ($d in @($destLive,$destPictures,$destVideos)) {
        if (-not (Test-Path -LiteralPath $d)) {
            if ($PSCmdlet.ShouldProcess($d, "Create folder")) {
                $null = New-Item -ItemType Directory -Path $d
            }
        }
    }

    # Unique-path helper to avoid overwriting
    function Get-UniquePath([string]$TargetPath) {
        if (-not (Test-Path -LiteralPath $TargetPath)) { return $TargetPath }
        $dir  = Split-Path -Path $TargetPath -Parent
        $name = [System.IO.Path]::GetFileNameWithoutExtension($TargetPath)
        $ext  = [System.IO.Path]::GetExtension($TargetPath)
        $i = 1
        while ($true) {
            $try = Join-Path $dir ("{0} ({1}){2}" -f $name,$i,$ext)
            if (-not (Test-Path -LiteralPath $try)) { return $try }
            $i++
        }
    }

    # Move helper
    function Move-Set([System.IO.FileInfo[]]$files, [string]$dest, [string]$label) {
        $count = 0
        foreach ($f in $files) {
            $target = Get-UniquePath (Join-Path $dest $f.Name)
            if ($PSCmdlet.ShouldProcess($f.FullName, "Move to '$target'")) {
                Move-Item -LiteralPath $f.FullName -Destination $target
                $count++
            }
        }
        Write-Host ("Moved {0} {1}." -f $count, $label)
    }

    # Execute moves
    Write-Host "Summary (top-level only):"
    Write-Host ("  Live Photo MOVs : {0}" -f $($liveMovs.Count))
    Write-Host ("  Pictures        : {0}" -f $($pictures.Count))
    Write-Host ("  Videos          : {0}" -f $($videos.Count))

    Move-Set -files $liveMovs  -dest $destLive     -label "Live Photo video(s)"
    Move-Set -files $pictures  -dest $destPictures -label "picture(s)"
    Move-Set -files $videos    -dest $destVideos   -label "video(s)"

    Write-Host "Done."
    Write-Host "Destinations:"
    Write-Host "  $destLive"
    Write-Host "  $destPictures"
    Write-Host "  $destVideos"
}

function Add-FileNamePrefix {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FolderPath,
        [Parameter(Mandatory = $true)]
        [string]$Prefix
    )

    if (-not (Test-Path -LiteralPath $FolderPath -PathType Container)) {
        throw "Folder not found: $FolderPath"
    }

    $files = Get-ChildItem -LiteralPath $FolderPath -File
    foreach ($file in $files) {
        $newName = $Prefix + $file.Name
        if ($PSCmdlet.ShouldProcess($file.FullName, "Rename to '$newName'")) {
            Rename-Item -LiteralPath $file.FullName -NewName $newName
            Write-Host ("Renamed: {0} -> {1}" -f $file.Name, $newName)
        }
    }
}

function Rename-PhotosByDateTaken {
    <#
    .SYNOPSIS
        Renames image files (.jpg, .jpeg, .png) by their "Date taken" property (oldest → newest).

    .DESCRIPTION
        This cmdlet uses Windows Shell metadata to retrieve each photo's "Date taken" value,
        sorts the photos chronologically, and prefixes each filename with a zero-padded
        numeric counter (e.g., 001_IMG_1234.JPG).

        - Locale-aware: works with “Date taken”, “Opnamedatum”, “Aufnahmedatum”, etc.
        - Falls back to the file’s CreationTimeUtc if no DateTaken metadata is found.
        - Operates only on the top-level of the specified folder.
        - Supports a DryRun mode for safe preview before renaming.

    .PARAMETER FolderPath
        The folder containing the photos to rename. Defaults to the current directory.

    .PARAMETER DryRun
        If set to $true (default), shows what would happen without renaming.
        Set to $false to actually perform the rename.

    .EXAMPLE
        Rename-PhotosByDateTaken -FolderPath "E:\Pictures\2025\USA"

        Lists all photos in the folder sorted by their Date Taken, showing new names.

    .EXAMPLE
        Rename-PhotosByDateTaken -FolderPath "E:\Pictures\2025\USA" -DryRun:$false

        Performs the actual renaming using the discovered Date Taken order.

    .NOTES
        Relies on the Windows Shell COM interface for metadata.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$FolderPath = ".",
        [bool]$DryRun = $true
    )

    $AllowedExtensions = @('.jpg','.jpeg','.png')
    $TargetFolder = (Resolve-Path -LiteralPath $FolderPath).Path
    $PhotoFiles = Get-ChildItem -LiteralPath $TargetFolder -File |
        Where-Object { $AllowedExtensions -contains $_.Extension.ToLowerInvariant() }
    if (-not $PhotoFiles) { Write-Host "No matching image files found in $TargetFolder"; return }

    function Clean-TextValue([string]$InputText) {
        if ([string]::IsNullOrWhiteSpace($InputText)) { return $null }
        ($InputText -replace '(\p{Cf}|\u200E|\u200F|\u202A|\u202B|\u202C|\u202D|\u202E|\u00A0)', '' -replace '\s*-\s*','-' -replace '\s+',' ').Trim()
    }

    try { $ShellApplication = New-Object -ComObject Shell.Application } catch {
        Write-Error "Shell COM unavailable."; return
    }
    $ShellNamespace = $ShellApplication.Namespace($TargetFolder)
    if (-not $ShellNamespace) { Write-Error "Cannot access Shell namespace for $TargetFolder"; return }

    $DateTakenIndex = $null
    for ($i=0; $i -le 300; $i++) {
        $HeaderName = Clean-TextValue ($ShellNamespace.GetDetailsOf($null,$i))
        if ($HeaderName -and $HeaderName -match '^(?i)(date taken|opnamedatum|aufnahmedatum)$') {
            $DateTakenIndex = $i; break
        }
    }

    $Culture = [System.Globalization.CultureInfo]::CurrentCulture

    $PhotoMetadata = foreach ($Photo in $PhotoFiles) {
        $ShellItem = $ShellNamespace.ParseName($Photo.Name)
        $RawDateTaken = if ($DateTakenIndex -ne $null -and $ShellItem) { $ShellNamespace.GetDetailsOf($ShellItem,$DateTakenIndex) } else { $null }
        $CleanDateTaken = Clean-TextValue $RawDateTaken
        $ParsedDateLocal = $null
        if ($CleanDateTaken) {
            try { $ParsedDateLocal = [datetime]::Parse($CleanDateTaken,$Culture,[System.Globalization.DateTimeStyles]::AssumeLocal) } catch {}
        }
        if ($ParsedDateLocal) {
            $ParsedDateTakenUtc = [datetimeoffset]::new($ParsedDateLocal).ToUniversalTime()
            [pscustomobject]@{ FileObject=$Photo; OriginalName=$Photo.Name; SortDateUtc=$ParsedDateTakenUtc; Source='DateTaken' }
        } else {
            $ParsedDateTakenUtc = [datetimeoffset]::new($Photo.CreationTimeUtc)
            [pscustomobject]@{ FileObject=$Photo; OriginalName=$Photo.Name; SortDateUtc=$ParsedDateTakenUtc; Source='CreationTimeUtc' }
        }
    }

    $SortedPhotos = $PhotoMetadata | Sort-Object SortDateUtc, @{e={$_.OriginalName}}
    $StartNumber = 1

    # FIX: Proper digit width calculation
    $TotalCount = $SortedPhotos.Count + $StartNumber
    $DigitWidth = [Math]::Max(2,[int][Math]::Ceiling([Math]::Log10([double]([Math]::Max(1,$TotalCount)))))

    function Get-UniqueFileName($DirectoryPath,$ProposedName) {
        $Candidate = Join-Path $DirectoryPath $ProposedName
        if (-not (Test-Path -LiteralPath $Candidate)) { return $ProposedName }
        $Base = [IO.Path]::GetFileNameWithoutExtension($ProposedName)
        $Ext  = [IO.Path]::GetExtension($ProposedName)
        $i=1
        while ($true) {
            $Alt = "{0} ({1}){2}" -f $Base,$i,$Ext
            if (-not (Test-Path -LiteralPath (Join-Path $DirectoryPath $Alt))) { return $Alt }
            $i++
        }
    }

    "{0,-4} {1,-34} {2,-19} {3}" -f "No.","OldName","When(UTC)","NewName"
    $Counter = $StartNumber
    foreach ($Photo in $SortedPhotos) {
        $Prefix = ('{0:D' + $DigitWidth + '}') -f $Counter
        $ProposedName = "{0}_{1}" -f $Prefix,$Photo.OriginalName
        $UniqueName = Get-UniqueFileName $Photo.FileObject.DirectoryName $ProposedName
        "{0,-4} {1,-34} {2,-19} {3}" -f $Counter,$Photo.OriginalName,$Photo.SortDateUtc.ToString("yyyy-MM-dd HH:mm:ss"),$UniqueName
        if (-not $DryRun) {
            Rename-Item -LiteralPath $Photo.FileObject.FullName -NewName $UniqueName
        }
        $Counter++
    }

    if ($DryRun) {
        Write-Host "`n(DRY RUN) No files were renamed. Use -DryRun:`$false to execute changes." -ForegroundColor Yellow
    }
}

function Rename-VideosByCaptureDate {
    <#
    .SYNOPSIS
        Renames .mov and .mp4 files by their capture/creation date using ExifTool (oldest → newest).

    .DESCRIPTION
        Reads reliable video timestamps via ExifTool JSON and sorts chronologically.
        Priority (first hit wins):
            MediaCreateDate → CreateDate → TrackCreateDate → Keys:CreationDate → FileModifyDate
        Falls back to filesystem CreationTimeUtc if no metadata parses.
        Top-level only (non-recursive). Prints a preview table; set -DryRun:$false to rename.

    .PARAMETER FolderPath
        Folder containing the video files. Default: current directory.

    .PARAMETER ExifToolPath
        Path or command name for ExifTool. Default: 'exiftool.exe'.

    .PARAMETER DryRun
        Preview only when $true (default). Set to $false to perform the rename.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Position=0)]
        [string]$FolderPath = ".",
        [string]$ExifToolPath = "exiftool.exe",
        [bool]$DryRun = $true
    )

    # 1) Resolve folder and pick video files (top-level only)
    $AllowedExtensions = @('.mov', '.mp4')
    $TargetFolder = (Resolve-Path -LiteralPath $FolderPath).Path

    $VideoFiles = Get-ChildItem -LiteralPath $TargetFolder -File |
        Where-Object { $AllowedExtensions -contains $_.Extension.ToLowerInvariant() }

    if (-not $VideoFiles) {
        Write-Host "No matching video files found in $TargetFolder"
        return
    }

    # 2) Call ExifTool once for timestamps (JSON)
    # Ask for multiple tags explicitly, and normalize QT times to UTC where possible.
    $ExifArgs = @(
        "-q","-q","-m","-json",
        "-api","QuickTimeUTC=1",
        "-d","%Y-%m-%dT%H:%M:%S%z",
        "-MediaCreateDate",
        "-CreateDate",
        "-TrackCreateDate",
        "-Keys:CreationDate",
        "-FileModifyDate",
        "-ext","mov","-ext","mp4",
        $TargetFolder
    )
    $ExifJson = & $ExifToolPath @ExifArgs
    $ExifItems = @()
    if ($ExifJson) { $ExifItems = $ExifJson | ConvertFrom-Json }

    # Map: normalized full path -> metadata object
    function Normalize-FullPath([string]$p) {
        if ([string]::IsNullOrWhiteSpace($p)) { return $null }
        return ([System.IO.Path]::GetFullPath($p))
    }
    $MetadataByPath = @{}
    foreach ($item in $ExifItems) {
        $sf = Normalize-FullPath $item.SourceFile
        if ($sf) { $MetadataByPath[$sf] = $item }
    }

    # 3) Robust datetime parser -> UTC
    function Convert-ToUtcDto([string]$Text) {
        if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
        $formats = @(
            'yyyy-MM-ddTHH:mm:ss.fffzzz',
            'yyyy-MM-ddTHH:mm:sszzz',
            'yyyy-MM-dd HH:mm:sszzz',
            'yyyy:MM:dd HH:mm:ss',
            'yyyy-MM-dd HH:mm:ss'
        )
        foreach ($fmt in $formats) {
            try {
                $dt = [datetimeoffset]::ParseExact(
                    $Text,
                    $fmt,
                    [Globalization.CultureInfo]::InvariantCulture,
                    [Globalization.DateTimeStyles]::None
                )
                return $dt.ToUniversalTime()
            } catch {}
        }
        try {
            return ([datetimeoffset]::Parse($Text, [Globalization.CultureInfo]::InvariantCulture)).ToUniversalTime()
        } catch {
            return $null
        }
    }

    # 4) Build records with chosen UTC date (and which tag was used)
    $VideoRecords = foreach ($video in $VideoFiles) {
        $meta = $MetadataByPath[(Normalize-FullPath $video.FullName)]

        # Ordered tag candidates (label -> value)
        $candidates = [ordered]@{}
        if ($meta) {
            $candidates["MediaCreateDate"]   = $meta.MediaCreateDate
            $candidates["CreateDate"]        = $meta.CreateDate
            $candidates["TrackCreateDate"]   = $meta.TrackCreateDate
            $candidates["Keys:CreationDate"] = $meta.'Keys:CreationDate'
            $candidates["FileModifyDate"]    = $meta.FileModifyDate
        }

        $utcDto   = $null
        $usedTag  = $null
        foreach ($kv in $candidates.GetEnumerator()) {
            $utcDto = Convert-ToUtcDto $kv.Value
            if ($utcDto) { $usedTag = $kv.Key; break }
        }

        if (-not $utcDto) {
            $utcDto  = [datetimeoffset]::new($video.CreationTimeUtc)
            $usedTag = 'CreationTimeUtc'
        }

        [pscustomobject]@{
            FileObject   = $video
            OriginalName = $video.Name
            SortDateUtc  = $utcDto
            UtcSeconds   = $utcDto.ToUnixTimeSeconds()
            SourceTag    = $usedTag
        }
    }

    # 5) Sort and compute padded width (robust)
    $SortedVideos = $VideoRecords | Sort-Object UtcSeconds, @{e={$_.OriginalName}}
    $StartIndex = 1
    $DigitWidth = [Math]::Max(
        2,
        [int][Math]::Ceiling(
            [Math]::Log10([double]([Math]::Max(1, $SortedVideos.Count + $StartIndex)))
        )
    )

    # Uniqueness helper
    function Get-UniqueFileName($DirectoryPath, $ProposedName) {
        $FullCandidatePath = Join-Path $DirectoryPath $ProposedName
        if (-not (Test-Path -LiteralPath $FullCandidatePath)) { return $ProposedName }
        $Base = [IO.Path]::GetFileNameWithoutExtension($ProposedName)
        $Ext  = [IO.Path]::GetExtension($ProposedName)
        $i = 1
        while ($true) {
            $Alt = "{0} ({1}){2}" -f $Base, $i, $Ext
            if (-not (Test-Path -LiteralPath (Join-Path $DirectoryPath $Alt))) { return $Alt }
            $i++
        }
    }

    # 6) Preview / Rename
    "{0,-4} {1,-34} {2,-19} {3} {4}" -f "No.", "OldName", "When(UTC)", "NewName", "Source"

    $Counter = $StartIndex
    foreach ($video in $SortedVideos) {
        $Prefix = ('{0:D' + $DigitWidth + '}') -f $Counter
        $NewName = "{0}_{1}" -f $Prefix, $video.OriginalName
        $UniqueName = Get-UniqueFileName $video.FileObject.DirectoryName $NewName

        "{0,-4} {1,-34} {2,-19} {3} {4}" -f $Counter, $video.OriginalName, $video.SortDateUtc.ToString("yyyy-MM-dd HH:mm:ss"), $UniqueName, $video.SourceTag

        if (-not $DryRun) {
            Rename-Item -LiteralPath $video.FileObject.FullName -NewName $UniqueName
        }
        $Counter++
    }

    if ($DryRun) {
        Write-Host "`n(DRY RUN) No files were renamed. Use -DryRun:`$false to apply changes." -ForegroundColor Yellow
    }
}

# Exported functions
Export-ModuleMember -Function Group-iPhoneMedia
Export-ModuleMember -Function Invoke-SyncFolders
Export-ModuleMember -Function Add-FileNamePrefix
Export-ModuleMember -Function Rename-VideosByCaptureDate
Export-ModuleMember -Function Rename-PhotosByDateTaken
