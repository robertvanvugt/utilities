# Example usages for Group-iPhoneMedia from the Utilities module
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
# Example usages Group-iPhoneMedia
#######################

# Set the source and destination folders (edit as needed)

$source = "E:\Pictures\2025\Vakantie USA 2025"

# Validate folders exist
if (-not (Test-Path $source -PathType Container)) {
    Write-Error "Source folder does not exist: $source"
    return
}

# Preview only (no changes)
Group-iPhoneMedia -Path $source -WhatIf -Verbose

# Actual move (no preview)
Group-iPhoneMedia -Path $source -Verbose

