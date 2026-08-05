; Built with Inno Setup (https://jrsoftware.org/isinfo.php) - free and
; open-source, commonly used for exactly this kind of installer.
;
; Flow:
;   1. Ask Windows for admin rights (PrivilegesRequired=admin below)
;   2. Check whether this machine is x64 or ARM64
;   3. Ask GitHub's API for this repo's latest release to find the current
;      version, then download the matching .msix + signing cert - using
;      Inno's own built-in CreateDownloadPage, which handles the progress
;      bar, retries, and error reporting natively. This is the same
;      pattern used in Inno's own official example script
;      (CodeDownloadFiles.iss).
;   4. Install the cert into Trusted People (see note below on why not
;      Trusted Root) - shown in a visible PowerShell window
;   5. Trigger the .msix install (also visible), then resolve its Start
;      Menu entry so a "Launch FluentFlyout" checkbox can appear on the
;      Finish page
;   6. Clean up the downloaded files
;
; This installer never goes out of date and never needs rebuilding when a
; new FluentFlyout version comes out - it asks GitHub for the current
; release version at install time, every time.

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

// Looks up TargetFilename's expected hash from SHA256SUMS.txt content
// (format: "<hash>  <filename>" per line, same as sign-packages produces).
// Returns '' if not found - callers treat that as "skip verification"
// rather than failing the whole install over it.
function ParseHashForFile(const SumsContent, TargetFilename: String): String;
var
	Lines, Parts: TArrayOfString;
	I: Integer;
begin
	Result := '';
	Lines := StringSplit(SumsContent, [#13#10, #10], stExcludeEmpty);
	for I := 0 to GetArrayLength(Lines) - 1 do
	begin
		if Pos(TargetFilename, Lines[I]) > 0 then
		begin
			Parts := StringSplit(Trim(Lines[I]), [' '], stExcludeEmpty);
			if GetArrayLength(Parts) > 0 then
			begin
				Result := Parts[0];
				Exit;
			end;
		end;
	end;
end;

procedure InitializeWizard();
begin
	DownloadPage := CreateDownloadPage('Downloading FluentFlyout',
		'Please wait while the required files are downloaded.', nil);
end;

// Pulls a single string value out of a JSON response, e.g. Key='tag_name'
// returns v2.13.1 from ..."tag_name": "v2.13.1"... Deliberately minimal -
// we need exactly one field, so a full JSON parser would be overkill.
// Tolerates whitespace around the colon, since GitHub's API returns
// pretty-printed JSON.
function ExtractJsonString(const Json, Key: String): String;
var
	P, Q: Integer;
begin
	Result := '';
	P := Pos('"' + Key + '"', Json);
	if P = 0 then
		Exit;
	P := P + Length(Key) + 2;
	// Skip forward to the colon that follows the key
	while (P <= Length(Json)) and (Json[P] <> ':') do
		P := P + 1;
	P := P + 1;
	// Then to the opening quote of the value
	while (P <= Length(Json)) and (Json[P] <> '"') do
		P := P + 1;
	P := P + 1;
	Q := P;
	while (Q <= Length(Json)) and (Json[Q] <> '"') do
		Q := Q + 1;
	Result := Copy(Json, P, Q - P);
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
	VersionAnsi, AppIdAnsi, SumsAnsi: AnsiString;
	CertUrl, MsixUrl, SumsUrl, SumsContent: String;
	CertHash, MsixHash: String;
	TrustScript, InstallScript: String;
	AppIdPath, VersionPath, SumsPath: String;
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
		VersionPath := TempDir + '\latest-release.json';

		// Step 3a: find the current version by asking GitHub directly for
		// this repo's latest release. /releases/latest deliberately
		// EXCLUDES prereleases - a prerelease here means the installer
		// itself failed smoke testing for that build, so end users should
		// land on the last known-good stable release instead.
		try
			DownloadTemporaryFile('https://api.github.com/repos/tanzim2000/fluentflyout-unofficial/releases/latest',
				'latest-release.json', '', nil);
		except
			MsgBox('Could not check the current FluentFlyout version. Check your internet connection and try again.' + #13#10 +
				GetExceptionMessage, mbCriticalError, MB_OK);
			Exit;
		end;
		if not LoadStringFromFile(VersionPath, VersionAnsi) then
		begin
			MsgBox('Could not read the version information downloaded from GitHub.', mbCriticalError, MB_OK);
			Exit;
		end;
		Version := Trim(ExtractJsonString(String(VersionAnsi), 'tag_name'));
		if Version = '' then
		begin
			MsgBox('Could not determine the latest FluentFlyout version from GitHub''s response.', mbCriticalError, MB_OK);
			Exit;
		end;

		CertUrl := 'https://github.com/tanzim2000/fluentflyout-unofficial/releases/download/' + Version + '/signing.cer';
		MsixUrl := 'https://github.com/tanzim2000/fluentflyout-unofficial/releases/download/' + Version + '/FluentFlyout_' + Version + '_' + Arch + '.msix';

		// Step 3b: look up expected hashes from the published checksum
		// manifest, so the download can be verified the same way
		// chocolateyinstall.ps1 already does. Non-fatal if this fails -
		// we proceed without verification rather than blocking the
		// install over a missing manifest.
		SumsPath := TempDir + '\SHA256SUMS.txt';
		CertHash := '';
		MsixHash := '';
		SumsUrl := 'https://github.com/tanzim2000/fluentflyout-unofficial/releases/download/' + Version + '/SHA256SUMS.txt';
		try
			DownloadTemporaryFile(SumsUrl, 'SHA256SUMS.txt', '', nil);
			if LoadStringFromFile(SumsPath, SumsAnsi) then
			begin
				SumsContent := String(SumsAnsi);
				CertHash := ParseHashForFile(SumsContent, 'signing.cer');
				MsixHash := ParseHashForFile(SumsContent, 'FluentFlyout_' + Version + '_' + Arch + '.msix');
			end;
		except
			// Leave both hashes as '' - DownloadPage.Add treats that as
			// "skip verification for this file".
		end;

		// Step 3c: download the cert + matching .msix, with Inno's own
		// native download progress page
		DownloadPage.Clear;
		DownloadPage.Add(CertUrl, 'signing.cer', CertHash);
		DownloadPage.Add(MsixUrl, 'app.msix', MsixHash);
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
		DeleteFile(SumsPath);
	end;
end;
