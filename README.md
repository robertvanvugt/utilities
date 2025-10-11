# Utilities PowerShell Repository

Reusable PowerShell module and helper scripts for file/media management tasks.

## Contents

- [modules/Utilities.psm1](modules/Utilities.psm1)
- [modules/Utilities.psd1](modules/Utilities.psd1)
- Example scripts in `Use-UtilityModuleFunctions.ps1`, `powershell-scripts/`

## Installation

```powershell
# Copy to your user module path
$dest = "$HOME\Documents\PowerShell\Modules\Utilities"
New-Item -ItemType Directory -Path $dest -Force | Out-Null
Copy-Item .\modules\Utilities.* $dest -Force
Import-Module Utilities
```

Or import directly:

```powershell
Import-Module .\modules\Utilities.psd1
```

## Exported Functions

| Function | Purpose |
|----------|---------|
| [`Invoke-SyncFolders`](modules/Utilities.psm1) | Two‑phase folder sync with hash/size/time diffing and reverse orphan handling. |
| [`Group-iPhoneMedia`](modules/Utilities.psm1) | Classifies top‑level iPhone media into LivePhotos / Pictures / Videos using ExifTool. |
| [`Add-FileNamePrefix`](modules/Utilities.psm1) | Adds a static prefix to all filenames in a folder (supports -WhatIf/-Confirm). |
| [`Rename-PhotosByDateTaken`](modules/Utilities.psm1) | Renames JPG/JPEG/PNG by “Date taken” (Shell COM) with chronological numbering. |
| [`Rename-VideosByCaptureDate`](modules/Utilities.psm1) | Renames MOV/MP4 by metadata capture date (ExifTool) with numbering. |

## Function Details

### Invoke-SyncFolders

Forward phase (source → destination) then reverse phase (destination → source) for orphans/diffs. Hashes (SHA256) skipped for files over `-HashThreshold`. Interactive action selection: Copy / Overwrite / Duplicate / Skip. Supports include/exclude extensions.
Examples:

```powershell
Invoke-SyncFolders -SourceFolder C:\Data -DestinationFolder D:\Backup
Invoke-SyncFolders -SourceFolder .\A -DestinationFolder .\B -IncludeExtensions '.jpg','.mp4'
Invoke-SyncFolders -SourceFolder .\A -DestinationFolder .\B -NoCheckHash
```

### Group-iPhoneMedia

Detects Live Photo MOVs (`Keys:LivePhotoAuto == 1`) via ExifTool; moves files into LivePhotos / Pictures / Videos (no recursion). Avoids overwrites by auto‑incrementing.

```powershell
Group-iPhoneMedia -Path "E:\Pictures\Import" -Verbose -WhatIf
Group-iPhoneMedia -Path "E:\Pictures\Import" -ExifToolPath "C:\Tools\exiftool.exe"
```

### Add-FileNamePrefix

Prefixes all top‑level files in a folder. Supports -WhatIf/-Confirm.

```powershell
Add-FileNamePrefix -FolderPath "C:\Temp\Photos" -Prefix "USA_" -WhatIf
Add-FileNamePrefix -FolderPath "C:\Temp\Photos" -Prefix "USA_" -Confirm
```

### Rename-PhotosByDateTaken

Reads localized “Date taken” column via Shell COM; falls back to CreationTimeUtc. Sequential, zero‑padded numbering; collision avoidance with “ (n)” suffix.

```powershell
Rename-PhotosByDateTaken -FolderPath "E:\Pictures\Trip"          # Dry run (default)
Rename-PhotosByDateTaken -FolderPath "E:\Pictures\Trip" -DryRun:$false
```

### Rename-VideosByCaptureDate

Single ExifTool JSON call; priority:
MediaCreateDate → CreateDate → TrackCreateDate → Keys:CreationDate → FileModifyDate → CreationTimeUtc (fallback).

```powershell
Rename-VideosByCaptureDate -FolderPath "E:\Videos"                # Preview
Rename-VideosByCaptureDate -FolderPath "E:\Videos" -DryRun:$false
Rename-VideosByCaptureDate -FolderPath "E:\Videos" -ExifToolPath "C:\Tools\exiftool.exe"
```

## Examples (Combined)

```powershell
Import-Module Utilities

Invoke-SyncFolders -SourceFolder C:\Source -DestinationFolder D:\Dest
Group-iPhoneMedia -Path C:\Import -WhatIf
Add-FileNamePrefix -FolderPath C:\Photos -Prefix "EVENT_" -WhatIf
Rename-PhotosByDateTaken -FolderPath C:\Photos -DryRun:$false
Rename-VideosByCaptureDate -FolderPath C:\Videos -DryRun:$false
```

## Notes

- ExifTool required for media classification and video timestamp extraction.
- Operations are top-level only (non-recursive) unless stated otherwise.
- Large file hash skipping threshold configurable via `-HashThreshold`.

## Contributing

Add new functions to [modules/Utilities.psm1](modules/Utilities.psm1), export them in [modules/Utilities.psd1](modules/Utilities.psd1), and update this README.

## License

MIT License (see repository root if present).
