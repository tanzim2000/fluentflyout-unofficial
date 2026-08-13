$ErrorActionPreference = 'Stop'

$packageName = 'fluentflyout-unofficial'
$rawVersion  = $env:ChocolateyPackageVersion
$version     = $rawVersion -replace '-untested$', '' -replace '^(\d+\.\d+\.\d+)\.\d+$', '$1'   # strip the "-untested" tag and, if present, a trailing 4th revision segment - clean 3-segment versions (e.g. 2.14.0) pass through unchanged
$repoBase    = "https://github.com/tanzim2000/fluentflyout-unofficial/releases/download/v$version"

$toolsDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$certUrl  = "$repoBase/signing.cer"
$certPath = Join-Path $toolsDir "signing.cer"

# Detect architecture
$arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'ARM64' } else { 'x64' }
$msixPath = Join-Path $toolsDir "FluentFlyout_$arch.msix"

Write-Host "Detected architecture: $arch"
Write-Host "Downloading FluentFlyout ($arch) v$version..."

# Each architecture's download is written out in full, with its checksum as a
# plain literal right on the Get-ChocolateyWebFile call, rather than passing a
# variable set by an if/else. This is functionally the same, but keeps the
# checksum statically tied to its download so Chocolatey's package validator
# can see it (a conditionally-assigned $msixHash variable can trip CPMR0073,
# "script does not validate downloaded files").
if ($arch -eq 'ARM64') {
	Get-ChocolateyWebFile -PackageName $packageName -FileFullPath $msixPath -Url "$repoBase/FluentFlyout_v${version}_ARM64.msix" -Checksum '__ARM64_SHA256__' -ChecksumType 'sha256'
} else {
	Get-ChocolateyWebFile -PackageName $packageName -FileFullPath $msixPath -Url "$repoBase/FluentFlyout_v${version}_x64.msix" -Checksum '__X64_SHA256__' -ChecksumType 'sha256'
}

Get-ChocolateyWebFile -PackageName $packageName -FileFullPath $certPath -Url $certUrl -Checksum '__CERT_SHA256__' -ChecksumType 'sha256'

# Self-signed certs used to sign MSIX packages are leaf certs, not CAs, so
# Windows' AppX validator requires them in the Trusted People store rather
# than Trusted Root - confirmed via a real installation failure
# (0x800B0109) that only resolved once the cert was placed here instead.
Write-Host "Trusting the package signing certificate (Local Machine, Trusted People)..."
Import-Certificate -FilePath $certPath -CertStoreLocation Cert:\LocalMachine\TrustedPeople | Out-Null

Write-Host "Installing FluentFlyout..."
Add-AppxPackage -Path $msixPath

Write-Host "FluentFlyout installed successfully."
