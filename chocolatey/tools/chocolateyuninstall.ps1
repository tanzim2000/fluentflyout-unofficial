$ErrorActionPreference = 'Stop'

$package = Get-AppxPackage -Name "*FluentFlyout*"

if ($package) {
    Write-Host "Removing FluentFlyout..."
    Remove-AppxPackage -Package $package.PackageFullName
    Write-Host "FluentFlyout removed."
} else {
    Write-Warning "FluentFlyout package not found — it may have already been removed."
}
