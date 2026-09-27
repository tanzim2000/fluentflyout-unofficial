$ErrorActionPreference = 'Stop'

$toolsDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$certPath = Join-Path $toolsDir "signing.cer"

# FluentFlyout is also distributed by the Microsoft Store, under a
# different publisher identity. The previous version of this script
# matched by name alone ("*FluentFlyout*"), which could also catch a
# side-by-side Store install (and could return more than one package,
# which Remove-AppxPackage can't take at once). Scoping to this
# project's own publisher - matching the Package.appxmanifest patch
# applied at build time - guarantees this uninstall can never touch
# anything but this project's own build.
$packages = Get-AppxPackage -Publisher 'CN=tanzim2000*'

if ($packages) {
	foreach ($package in $packages) {
		Write-Host "Removing FluentFlyout ($($package.PackageFullName))..."
		Remove-AppxPackage -Package $package.PackageFullName
	}
	Write-Host "FluentFlyout removed."
} else {
	Write-Warning "FluentFlyout (this project's build) not found — it may have already been removed."
}

# Remove only the exact certificate this package itself installed,
# identified by its thumbprint (read from the signing.cer Chocolatey kept
# alongside this script, not re-downloaded), rather than clearing Trusted
# People wholesale - which could remove a certificate some other,
# unrelated app on the machine still depends on.
if (Test-Path $certPath) {
	$cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($certPath)
	Write-Host "Removing signing certificate (Local Machine, Trusted People, thumbprint $($cert.Thumbprint))..."
	Get-ChildItem Cert:\LocalMachine\TrustedPeople |
		Where-Object { $_.Thumbprint -eq $cert.Thumbprint } |
		Remove-Item -ErrorAction SilentlyContinue
} else {
	Write-Warning "signing.cer not found in the package's tools folder; skipping certificate removal."
}
