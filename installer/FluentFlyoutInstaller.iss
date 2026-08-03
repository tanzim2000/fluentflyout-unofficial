; Built with Inno Setup (https://jrsoftware.org/isinfo.php) - free and
; open-source, commonly used for exactly this kind of installer.
;
; Flow:
;   1. Ask Windows for admin rights (PrivilegesRequired=admin below)
;   2. Check whether this machine is x64 or ARM64
;   3. Look up the current version, then download the matching .msix +
;      signing cert - using Inno's own built-in CreateDownloadPage, which
;      handles the progress bar, retries, and error reporting natively.
;      This is the same pattern used in Inno's own official example
;      script (CodeDownloadFiles.iss).
;   4. Install the cert into Trusted People (see note below on why not
;      Trusted Root) - shown in a visible PowerShell window
;   5. Trigger the .msix install (also visible), then resolve its Start
;      Menu entry so a "Launch FluentFlyout" checkbox can appear on the
;      Finish page
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

[Run]
; This is what makes the "Launch FluentFlyout" checkbox appear on the
; Finish page. CanLaunchApp / GetAppLaunchID are defined below in [Code] -
; the checkbox only shows up if we actually managed to resolve the app's
; Start Menu entry after installing it.
Filename: "{sys}\explorer.exe"; Parameters: "shell:appsFolder\{code:GetAppLaunchID}"; Description: "Launch FluentFlyout"; Flags: postinstall nowait skipifsilent; Check: CanLaunchApp

[Code]
var
	DownloadPage: TDownloadWizardPage;
	AppLaunchID: String;

function GetAppLaunchID(Param: String): String;
begin
	Result := AppLaunchID;
end;

function CanLaunchApp(): Boolean;
begin
	Result := AppLaunchID <> '';
end;

procedure InitializeWizard();
begin
	DownloadPage := CreateDownloadPage('Downloading FluentFlyout',
		'Please wait while the required files are downloaded.', nil);
end;

// Writes a PowerShell script to a temp file and runs it. ShowCmd controls
// window visibility (SW_HIDE or SW_SHOW).
procedure RunScript(const ScriptContent, ScriptName: String; ShowCmd: Integer);
var
	ScriptPath: String;
	ResultCode: Integer;
begin
	ScriptPath := ExpandConstant('{tmp}\') + ScriptName;
	SaveStringToFile(ScriptPath, ScriptContent, False);
	Exec('powershell.exe', '-NoProfile -ExecutionPolicy Bypass -File "' + ScriptPath + '"',
		'', ShowCmd, ewWaitUntilTerminated, ResultCode);
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
	Arch, TempDir, Version: String;
	VersionAnsi, AppIdAnsi: AnsiString;
	CertUrl, MsixUrl: String;
	TrustScript, InstallScript: String;
	AppIdPath, VersionPath: String;
begin
	if CurStep = ssPostInstall then
	begin
		// Step 2: check the system
		if IsArm64() then
			Arch := 'ARM64'
		else
			Arch := 'x64';

		TempDir := ExpandConstant('{tmp}');
		AppIdPath := TempDir + '\appid.txt';
		VersionPath := TempDir + '\last_built_version.txt';

		// Step 3a: find the current version
		try
			DownloadTemporaryFile('https://raw.githubusercontent.com/tanzim2000/fluentflyout-unofficial/refs/heads/main/last_built_version.txt',
				'last_built_version.txt', '', nil);
		except
			MsgBox('Could not check the current FluentFlyout version. Check your internet connection and try again.' + #13#10 +
				GetExceptionMessage, mbCriticalError, MB_OK);
			Exit;
		end;
		if not LoadStringFromFile(VersionPath, VersionAnsi) then
		begin
			MsgBox('Could not read the downloaded version file.', mbCriticalError, MB_OK);
			Exit;
		end;
		Version := Trim(String(VersionAnsi));

		CertUrl := 'https://github.com/tanzim2000/fluentflyout-unofficial/releases/download/' + Version + '/signing.cer';
		MsixUrl := 'https://github.com/tanzim2000/fluentflyout-unofficial/releases/download/' + Version + '/FluentFlyout_' + Version + '_' + Arch + '.msix';

		// Step 3b: download the cert + matching .msix, with Inno's own
		// native download progress page
		DownloadPage.Clear;
		DownloadPage.Add(CertUrl, 'signing.cer', '');
		DownloadPage.Add(MsixUrl, 'app.msix', '');
		DownloadPage.Show;
		try
			try
				DownloadPage.Download;
			except
				if DownloadPage.AbortedByUser then
					MsgBox('Download cancelled.', mbInformation, MB_OK)
				else
					MsgBox('Download failed: ' + GetExceptionMessage, mbCriticalError, MB_OK);
				Exit;
			end;
		finally
			DownloadPage.Hide;
		end;

		// Step 4: trust the certificate. This goes into Trusted People,
		// not Trusted Root - confirmed by testing that self-signed leaf
		// certs (which is what this project's signing cert is) are only
		// honored by Windows' AppX validator from Trusted People, even
		// when the same cert sitting in Trusted Root gets rejected.
		TrustScript :=
			'$ErrorActionPreference = ''Stop''' + #13#10 +
			'Import-Certificate -FilePath ''' + TempDir + '\signing.cer'' -CertStoreLocation Cert:\LocalMachine\TrustedPeople | Out-Null';
		RunScript(TrustScript, 'trust.ps1', SW_SHOW);

		// Step 5: install, then resolve the launch AppID so the "Launch
		// FluentFlyout" checkbox on the Finish page works. MSIX apps
		// don't have a fixed .exe path to launch directly, so we build
		// shell:appsFolder\<PackageFamilyName>!<AppId> from the installed
		// package's own manifest - not from Get-StartApps, since that
		// reads Windows' Start Menu index, which can lag behind
		// Add-AppxPackage actually finishing.
		InstallScript :=
			'$ErrorActionPreference = ''Stop''' + #13#10 +
			'Add-AppxPackage -Path ''' + TempDir + '\app.msix''' + #13#10 +
			'$pkg = Get-AppxPackage | Where-Object { $_.Name -like ''*FluentFlyout*'' } | Select-Object -First 1' + #13#10 +
			'if ($pkg) {' + #13#10 +
			'  $manifest = Get-AppxPackageManifest -Package $pkg.PackageFullName' + #13#10 +
			'  $appId = $manifest.Package.Applications.Application.Id' + #13#10 +
			'  if ($appId) { Set-Content -Path ''' + AppIdPath + ''' -Value ($pkg.PackageFamilyName + ''!'' + $appId) -NoNewline }' + #13#10 +
			'}';
		RunScript(InstallScript, 'install.ps1', SW_SHOW);

		if LoadStringFromFile(AppIdPath, AppIdAnsi) then
			AppLaunchID := String(AppIdAnsi)
		else
			AppLaunchID := '';

		// Step 6: clean up. Inno automatically wipes {tmp} (where all the
		// downloaded files live) once Setup finishes, so this just
		// removes the couple of files we wrote directly ourselves.
		DeleteFile(AppIdPath);
		DeleteFile(VersionPath);
	end;
end;
