$ErrorActionPreference = 'Stop'

$packageName = 'fluentflyout-unofficial'
$rawVersion  = $env:ChocolateyPackageVersion
$version     = $rawVersion -replace '-untested$', '' -replace '\.\d+$', ''   # strip both the "-untested" tag and the run-number revision segment; GitHub release tags have neither
$repoBase    = "https://github.com/tanzim2000/fluentflyout-unofficial/releases/download/v$version"

# Detect architecture
$arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'ARM64' } else { 'x64' }

$msixUrl  = "$repoBase/FluentFlyout_v${version}_$arch.msix"
$certUrl  = "$repoBase/signing.cer"
$msixHash = if ($arch -eq 'ARM64') { '__ARM64_SHA256__' } else { '__X64_SHA256__' }
$certHash = '__CERT_SHA256__'

$toolsDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$msixPath = Join-Path $toolsDir "FluentFlyout_$arch.msix"
$certPath = Join-Path $toolsDir "signing.cer"

Write-Host "Detected architecture: $arch"
Write-Host "Downloading FluentFlyout ($arch) v$version..."

Get-ChocolateyWebFile -PackageName $packageName -FileFullPath $msixPath -Url $msixUrl -Checksum $msixHash -ChecksumType 'sha256'
Get-ChocolateyWebFile -PackageName $packageName -FileFullPath $certPath -Url $certUrl -Checksum $certHash -ChecksumType 'sha256'

# Self-signed certs used to sign MSIX packages are leaf certs, not CAs, so
# Windows' AppX validator requires them in the Trusted People store rather
# than Trusted Root - confirmed via a real installation failure
# (0x800B0109) that only resolved once the cert was placed here instead.
Write-Host "Trusting the package signing certificate (Local Machine, Trusted People)..."
Import-Certificate -FilePath $certPath -CertStoreLocation Cert:\LocalMachine\TrustedPeople | Out-Null

Write-Host "Installing FluentFlyout..."
Add-AppxPackage -Path $msixPath

Write-Host "FluentFlyout installed successfully."
