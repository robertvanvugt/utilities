# Utilities PowerShell Module

A generic PowerShell module for reusable utility functions. This module is designed to collect useful scripts and helpers for file management and other automation tasks. As new utilities are added, they will be documented here.

## Installation

Copy the `Utilities.psm1` and `Utilities.psd1` files to a folder named `Utilities` under your PowerShell modules path (e.g. `~/Documents/PowerShell/Modules/Utilities`).

Import the module in your session:

```powershell
Import-Module Utilities
```

Or import directly from the folder:

```powershell
Import-Module 'C:\path\to\Utilities.psd1'
```

## Exported Functions

### Invoke-SyncFolders

Synchronizes files between two folders, with preview, interactive approval, and efficient hash checking. Also supports reverse orphan sync.

**Parameters:**

- `-SourceFolder <string>`: The source folder to sync from. (Required)
- `-DestinationFolder <string>`: The destination folder to sync to. (Required)
- `-NoCheckHash`: If specified, disables SHA256 file hash comparison (uses only size/timestamp).
- `-HashThreshold <string>`: Maximum file size to check hash (e.g. '2GB', '500MB'). Larger files only use size/timestamp. Default: '2GB'.

**Examples:**

```powershell
Invoke-SyncFolders -SourceFolder C:\Data -DestinationFolder D:\Backup
Invoke-SyncFolders -SourceFolder .\A -DestinationFolder .\B -HashThreshold 500MB
```

**Features:**

- Shows a preview of files/folders to be created or copied.
- Prompts for confirmation before copying.
- Efficiently skips large files from hash checking if above threshold.
- Optionally syncs orphan files back from destination to source.

---

## Adding More Utilities

More utility functions will be added over time.

---

## Credits

- **Author:** Robert van Vugt
- **Date:** 06 July 2025
