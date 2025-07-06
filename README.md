# Utilities PowerShell Repository

This repository contains reusable PowerShell modules and scripts designed to enhance the functionality, management, and maintenance of computer systems. The focus is on robust, production-ready utilities for file management, automation, and system administration.

## Structure

- `modules/` — Contains PowerShell modules (e.g., `Utilities.psm1`, `Utilities.psd1`) and their documentation.
- `Install-UtilitiesModules.ps1` — Script to install or update one or more modules from this repo to your user module path.
- `Invoke-SyncFolders-Examples.ps1` — Example script for using the `Invoke-SyncFolders` function from the Utilities module.

## Getting Started

1. **Install/Update Modules**
   - Use the provided installer script:
     ```powershell
     .\Install-UtilitiesModules.ps1
     ```
   - This will copy the latest modules to your PowerShell user module path and import them.

2. **Import the Utilities Module**
   - In your scripts or session:
     ```powershell
     Import-Module Utilities
     ```

3. **Use Utility Functions**
   - See `Invoke-SyncFolders-Examples.ps1` for usage examples.

## Available Utilities

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

---

## Contributing

Contributions are welcome! To add a new utility:
- Add your function to `modules/Utilities.psm1`.
- Export it in `modules/Utilities.psd1`.
- Document it in this README under **Available Utilities**.
- Add usage examples if possible.

## License

This repository is licensed under the MIT License.

---

**Author:** Robert van Vugt
