; Built with Inno Setup (https://jrsoftware.org/isinfo.php) - free and
; open-source, commonly used for exactly this kind of installer.
;
; Flow:
;   1. Ask Windows for admin rights (PrivilegesRequired=admin below)
;   2. Check whether this machine is x64 or ARM64
;   3. Read last_built_version.txt from the repo to find the current
;      version, then download the matching .msix + signing cert
;   4. Install the cert into Trusted Root
;   5. Trigger the .msix install
;   6. Clean up the downloaded files
;
; This installer never goes out of date and never needs rebuilding when a
; new FluentFlyout version comes out - it always reads the current
; version straight from the repo at install time.

[Setup]
AppName=FluentFlyout (Unofficial Build) Installer
AppVersion=1.0
PrivilegesRequired=admin
CreateAppDir=no
DisableDirPage=yes
DisableProgramGroupPage=yes
DisableReadyPage=yes
OutputDir=Output
OutputBaseFilename=FluentFlyout_Installer
Compression=lzma
SolidCompression=yes

[Code]
procedure CurStepChanged(CurStep: TSetupStep);
var
	ResultCode: Integer;
	Arch, TempDir, Script: String;
begin
	if CurStep = ssPostInstall then
	begin
		// Step 2: check the system
		if IsArm64() then
			Arch := 'ARM64'
		else
			Arch := 'x64';

		TempDir := ExpandConstant('{tmp}');

		// Steps 3-6 all run as one PowerShell call. $version is resolved
		// at runtime by PowerShell (from last_built_version.txt); Arch
		// above is resolved at compile-time by Inno and just gets pasted
		// into the command text directly.
		Script :=
			'$ErrorActionPreference=''Stop''; ' +
			'Write-Host ''Checking latest version...''; ' +
			'$version = (Invoke-WebRequest -Uri ''https://raw.githubusercontent.com/tanzim2000/fluentflyout-unofficial/refs/heads/main/last_built_version.txt'' -UseBasicParsing).Content.Trim(); ' +
			'$certUrl = ''https://github.com/tanzim2000/fluentflyout-unofficial/releases/download/'' + $version + ''/signing.cer''; ' +
			'$msixUrl = ''https://github.com/tanzim2000/fluentflyout-unofficial/releases/download/'' + $version + ''/FluentFlyout_'' + $version + ''_' + Arch + '.msix''; ' +
			'Write-Host (''Downloading FluentFlyout '' + $version + '' (' + Arch + ')...''); ' +
			'Invoke-WebRequest -Uri $certUrl -OutFile ''' + TempDir + '\signing.cer''; ' +
			'Invoke-WebRequest -Uri $msixUrl -OutFile ''' + TempDir + '\app.msix''; ' +
			'Write-Host ''Trusting certificate...''; ' +
			'Import-Certificate -FilePath ''' + TempDir + '\signing.cer'' -CertStoreLocation Cert:\LocalMachine\Root | Out-Null; ' +
			'Write-Host ''Installing app...''; ' +
			'Add-AppxPackage -Path ''' + TempDir + '\app.msix''; ' +
			'Write-Host ''Cleaning up...''; ' +
			'Remove-Item ''' + TempDir + '\signing.cer'', ''' + TempDir + '\app.msix'' -Force';

		Exec('powershell.exe',
			'-NoProfile -ExecutionPolicy Bypass -Command "' + Script + '"',
			'', SW_SHOW, ewWaitUntilTerminated, ResultCode);
	end;
end;
