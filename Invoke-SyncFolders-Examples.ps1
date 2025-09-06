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

$source = "E:\Pictures\2018"
$destination = "D:\Pictures\2018"

# Validate folders exist
if (-not (Test-Path $source -PathType Container)) {
    Write-Error "Source folder does not exist: $source"
    return
}
if (-not (Test-Path $destination -PathType Container)) {
    Write-Warning "Destination folder does not exist: $destination. It will be created if needed."
}

# Default: compares file hashes (Don't use this for large files or directories, as it can be slow)
Invoke-SyncFolders -SourceFolder $source -DestinationFolder $destination -NoCheckHash

# Same as above, but exclude files with .AAE extension (common for image metadata files)
# This is useful to avoid syncing metadata files that are not needed in the destination.
Invoke-SyncFolders -SourceFolder $source -DestinationFolder $destination -NoCheckHash -IncludeExtensions @('.JPEG')

# Example: compare file hashes for a different pair
Invoke-SyncFolders -SourceFolder "D:\source\tests" -DestinationFolder "E:\destination\test"

# Example: skip hash comparison (uses only size/timestamp)
Invoke-SyncFolders -SourceFolder $source -DestinationFolder $destination -NoCheckHash
