# Installs or updates one or more PowerShell modules from specified source folders to the user's module path
function Update-Modules {
    <#
    .SYNOPSIS
        Installs or updates one or more PowerShell modules in the user's module directory.
    .PARAMETER Modules
        An array of hashtables with Name and SourcePath for each module. E.g. @{ Name = 'Utilities'; SourcePath = 'C:\path\to\Utilities' }
    .EXAMPLE
        Update-UtilitiesModules -Modules @(@{ Name = 'Utilities'; SourcePath = 'C:\path\to\Utilities' })
    #>
    param(
        [Parameter(Mandatory)]
        [array]$Modules
    )
    foreach ($mod in $Modules) {
        $name = $mod.Name
        $src = $mod.SourcePath
        $ModulePath = Join-Path $env:USERPROFILE "Documents\PowerShell\Modules\$name"
        Write-Host "Installing/Updating $name module to: $ModulePath" -ForegroundColor Cyan
        Write-Host "Using source path: $src" -ForegroundColor Gray

        if (Get-Module -Name $name) {
            Write-Host "Removing existing module from session..." -ForegroundColor Yellow
            Remove-Module $name -Force
        }
        if (Test-Path $ModulePath) {
            Write-Host "Removing existing module files..." -ForegroundColor Yellow
            Remove-Item $ModulePath -Recurse -Force
        }
        New-Item -ItemType Directory -Path $ModulePath -Force | Out-Null
        Copy-Item (Join-Path $src '*.psm1') -Destination $ModulePath -Force
        Copy-Item (Join-Path $src '*.psd1') -Destination $ModulePath -Force
        Copy-Item (Join-Path $src '*.md')   -Destination $ModulePath -Force -ErrorAction SilentlyContinue

        Write-Host "Importing updated $name module..." -ForegroundColor Green
        Import-Module $name -Force
        $module = Get-Module $name
        if ($module) {
            Write-Host "✅ $name module successfully installed!" -ForegroundColor Green
            Write-Host "   Version: $($module.Version)" -ForegroundColor Gray
            Write-Host "   Path: $($module.ModuleBase)" -ForegroundColor Gray
            Write-Host "   Exported functions: $([string]::Join(', ', $module.ExportedCommands.Keys))" -ForegroundColor Magenta
        } else {
            Write-Error "❌ $name module installation failed!"
        }
    }
}

# Example usage for Utilities module
Update-Modules -Modules @(
    @{ Name = 'Utilities'; SourcePath = 'c:\_code\_github\robertvanvugt\utilities\modules'}
)
