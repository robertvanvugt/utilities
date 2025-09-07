# Example usages for Invoke-SyncFolders from the Utilities module
# Best practices: robust import, error handling, parameterization, and clear output

# Import the Utilities module (ensure it is installed in your user module path)
try {
    Import-Module Utilities -Force -ErrorAction Stop
    Write-Host "[OK] Utilities module imported." -ForegroundColor Green
} catch {
    Write-Error "[ERROR] Could not import the Utilities module. Ensure it is installed in your user module path. $_"
    return
}

#######################
# Example usages
#######################

# Set the source and destination folders (edit as needed)

$source = "C:\tmp\pics"

# Validate folders exist
if (-not (Test-Path $source -PathType Container)) {
    Write-Error "Source folder does not exist: $source"
    return
}

# Preview only (no changes made)
Set-LivePhotoTag -Path $source -WhatIf

# Actually tag the files
Set-LivePhotoTag -Path $source

# No recursion
Set-LivePhotoTag -Path $source -Recurse:$false

# Use a custom keyword
Set-LivePhotoTag -Path $source -Tag "AppleLivePhoto"