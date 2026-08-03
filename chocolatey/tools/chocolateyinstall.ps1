$ErrorActionPreference = 'Stop'

$packageName = 'fluentflyout-unofficial'
$rawVersion  = $env:ChocolateyPackageVersion
$version     = $rawVersion -replace '-untested$', ''   # GitHub release tags never have this suffix
$repoBase    = "https://github.com/tanzim2000/fluentflyout-unofficial/releases/download/v$version"

# Detect architecture
$arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'ARM64' } else { 'x64' }

$msixUrl  = "$repoBase/FluentFlyout_v${version}_$arch.msix"
$certUrl  = "$repoBase/signing.cer"
$msixHash = if ($arch -eq 'ARM64') { '__ARM64_SHA256__' } else { '__X64_SHA256__' }

$toolsDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$msixPath = Join-Path $toolsDir "FluentFlyout_$arch.msix"
$certPath = Join-Path $toolsDir "signing.cer"

Write-Host "Detected architecture: $arch"
Write-Host "Downloading FluentFlyout ($arch) v$version..."

Get-ChocolateyWebFile -PackageName $packageName -FileFullPath $msixPath -Url $msixUrl -Checksum $msixHash -ChecksumType 'sha256'
Get-ChocolateyWebFile -PackageName $packageName -FileFullPath $certPath -Url $certUrl

Write-Host "Trusting the package signing certificate (Local Machine, Trusted Root)..."
Import-Certificate -FilePath $certPath -CertStoreLocation Cert:\LocalMachine\Root | Out-Null

Write-Host "Installing FluentFlyout..."
Add-AppxPackage -Path $msixPath

Write-Host "FluentFlyout installed successfully."
