; Built with Inno Setup (https://jrsoftware.org/isinfo.php) - free and
; open-source, commonly used for exactly this kind of installer.
;
; Flow:
;   1. Ask Windows for admin rights (PrivilegesRequired=admin below)
;   2. Check whether this machine is x64 or ARM64
;   3. Read last_built_version.txt from the repo to find the current
;      version, then download the matching .msix + signing cert - with a
;      live byte-progress bar while the .msix downloads
;   4. Install the cert into Trusted People (see note below on why not
;      Trusted Root)
;   5. Trigger the .msix install, then resolve its Start Menu entry so a
;      "Launch FluentFlyout" checkbox can appear on the Finish page
;   6. Clean up the downloaded files
;
; This installer never goes out of date and never needs rebuilding when a
; new FluentFlyout version comes out - it always reads the current
; version straight from the repo at install time.
;
; All PowerShell work runs hidden (no visible console window). Progress
; is shown using Inno's own built-in progress controls (no third-party
; plugin) - a 4-stage overall progress bar, plus a second live byte-count
; progress bar that appears specifically while the .msix is downloading,
; so a slow connection doesn't look like the installer has frozen.

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
	ProgressPage: TOutputProgressWizardPage;
	DownloadLabel: TNewStaticText;
	DownloadBar: TNewProgressBar;
	AppLaunchID: String;

function GetAppLaunchID(Param: String): String;
begin
	Result := AppLaunchID;
end;

function CanLaunchApp(): Boolean;
begin
	Result := AppLaunchID <> '';
end;

// Formats a byte count as a human-readable MB figure, e.g. "12.4 MB"
function FormatMB(const Bytes: Int64): String;
begin
	Result := Format('%.1f MB', [Bytes / 1048576]);
end;

procedure InitializeWizard();
begin
	ProgressPage := CreateOutputProgressPage('Installing FluentFlyout',
		'Please wait while the installer downloads and sets up FluentFlyout.');

	// A second progress bar, placed just below the main one on the same
	// page, used specifically to show live byte progress while the
	// .msix downloads. Hidden the rest of the time.
	DownloadLabel := TNewStaticText.Create(ProgressPage);
	DownloadLabel.Parent := ProgressPage.Surface;
	DownloadLabel.Left := ProgressPage.ProgressBar.Left;
	DownloadLabel.Top := ProgressPage.ProgressBar.Top + ProgressPage.ProgressBar.Height + 12;
	DownloadLabel.Width := ProgressPage.ProgressBar.Width;
	DownloadLabel.Caption := '';
	DownloadLabel.Visible := False;

	DownloadBar := TNewProgressBar.Create(ProgressPage);
	DownloadBar.Parent := ProgressPage.Surface;
	DownloadBar.Left := ProgressPage.ProgressBar.Left;
	DownloadBar.Top := DownloadLabel.Top + DownloadLabel.Height + 4;
	DownloadBar.Width := ProgressPage.ProgressBar.Width;
	DownloadBar.Height := ProgressPage.ProgressBar.Height;
	DownloadBar.Min := 0;
	DownloadBar.Max := 100;
	DownloadBar.Position := 0;
	DownloadBar.Visible := False;
end;

// Writes a PowerShell script to a temp file and runs it hidden (no
// console window). Waits='true' blocks until it finishes; Waits='false'
// starts it and returns immediately, so we can poll progress meanwhile.
procedure RunHiddenScript(const ScriptContent, ScriptName: String; Wait: Boolean);
var
	ScriptPath: String;
	ResultCode: Integer;
begin
	ScriptPath := ExpandConstant('{tmp}\') + ScriptName;
	SaveStringToFile(ScriptPath, ScriptContent, False);
	if Wait then
		Exec('powershell.exe', '-NoProfile -ExecutionPolicy Bypass -File "' + ScriptPath + '"',
			'', SW_HIDE, ewWaitUntilTerminated, ResultCode)
	else
		Exec('powershell.exe', '-NoProfile -ExecutionPolicy Bypass -File "' + ScriptPath + '"',
			'', SW_HIDE, ewNoWait, ResultCode);
end;

// Polls the .msix file's size on disk while it downloads in the
// background, updating the second progress bar, until a "done" marker
// file appears. If we couldn't determine the expected size up front,
// falls back to just showing bytes downloaded so far.
procedure WatchDownloadProgress(const FilePath, DoneMarker: String; ExpectedSize: Int64);
var
	CurrentSize: Int64;
	Percent: Integer;
begin
	DownloadLabel.Visible := True;
	DownloadBar.Visible := True;
	while not FileExists(DoneMarker) do
	begin
		if FileExists(FilePath) and FileSize64(FilePath, CurrentSize) then
		begin
			if ExpectedSize > 0 then
			begin
				Percent := (CurrentSize * 100) div ExpectedSize;
				if Percent > 100 then
					Percent := 100;
				DownloadBar.Position := Percent;
				DownloadLabel.Caption := FormatMB(CurrentSize) + ' / ' + FormatMB(ExpectedSize);
			end
			else
			begin
				DownloadLabel.Caption := FormatMB(CurrentSize) + ' downloaded';
			end;
		end;
		Sleep(200);
	end;
	DownloadBar.Position := 100;
	DownloadLabel.Visible := False;
	DownloadBar.Visible := False;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
	Arch, TempDir: String;
	SizeScript, DownloadScript, TrustScript, InstallScript, CleanupScript: String;
	AppIdPath, SizePath, MsixPath, DoneMarkerPath: String;
	SizeAnsi, AppIdAnsi: AnsiString;
	ExpectedSize: Int64;
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
		SizePath := TempDir + '\size.txt';
		MsixPath := TempDir + '\app.msix';
		DoneMarkerPath := TempDir + '\download.done';

		ProgressPage.Show;
		try
			// Step 3a: find out how big the .msix actually is, so the
			// download progress bar below has a real total to work against
			ProgressPage.SetText('Preparing download...', '');
			ProgressPage.SetProgress(1, 4);
			SizeScript :=
				'$ErrorActionPreference = ''Stop''' + #13#10 +
				'$version = (Invoke-WebRequest -Uri ''https://raw.githubusercontent.com/tanzim2000/fluentflyout-unofficial/refs/heads/main/last_built_version.txt'' -UseBasicParsing).Content.Trim()' + #13#10 +
				'$msixUrl = ''https://github.com/tanzim2000/fluentflyout-unofficial/releases/download/'' + $version + ''/FluentFlyout_'' + $version + ''_' + Arch + '.msix''' + #13#10 +
				'try {' + #13#10 +
				'  $resp = Invoke-WebRequest -Uri $msixUrl -Method Head -UseBasicParsing -MaximumRedirection 5' + #13#10 +
				'  Set-Content -Path ''' + SizePath + ''' -Value $resp.Headers[''Content-Length''] -NoNewline' + #13#10 +
				'} catch { Set-Content -Path ''' + SizePath + ''' -Value ''0'' -NoNewline }';
			RunHiddenScript(SizeScript, 'size.ps1', True);

			ExpectedSize := 0;
			if LoadStringFromFile(SizePath, SizeAnsi) then
				ExpectedSize := StrToInt64Def(Trim(String(SizeAnsi)), 0);

			// Step 3b: start the real download in the background, then
			// watch its progress until the "done" marker appears
			ProgressPage.SetText('Downloading files...', '');
			ProgressPage.SetProgress(2, 4);
			DownloadScript :=
				'$ErrorActionPreference = ''Stop''' + #13#10 +
				'$version = (Invoke-WebRequest -Uri ''https://raw.githubusercontent.com/tanzim2000/fluentflyout-unofficial/refs/heads/main/last_built_version.txt'' -UseBasicParsing).Content.Trim()' + #13#10 +
				'$certUrl = ''https://github.com/tanzim2000/fluentflyout-unofficial/releases/download/'' + $version + ''/signing.cer''' + #13#10 +
				'$msixUrl = ''https://github.com/tanzim2000/fluentflyout-unofficial/releases/download/'' + $version + ''/FluentFlyout_'' + $version + ''_' + Arch + '.msix''' + #13#10 +
				'Invoke-WebRequest -Uri $certUrl -OutFile ''' + TempDir + '\signing.cer''' + #13#10 +
				'Invoke-WebRequest -Uri $msixUrl -OutFile ''' + MsixPath + '''' + #13#10 +
				'New-Item -Path ''' + DoneMarkerPath + ''' -ItemType File | Out-Null';
			RunHiddenScript(DownloadScript, 'download.ps1', False);
			WatchDownloadProgress(MsixPath, DoneMarkerPath, ExpectedSize);

			// Step 4: trust the certificate. This goes into Trusted People,
			// not Trusted Root - confirmed by testing that self-signed leaf
			// certs (which is what this project's signing cert is) are only
			// honored by Windows' AppX validator from Trusted People, even
			// when the same cert sitting in Trusted Root gets rejected.
			ProgressPage.SetText('Trusting certificate...', '');
			ProgressPage.SetProgress(3, 4);
			TrustScript :=
				'$ErrorActionPreference = ''Stop''' + #13#10 +
				'Import-Certificate -FilePath ''' + TempDir + '\signing.cer'' -CertStoreLocation Cert:\LocalMachine\TrustedPeople | Out-Null';
			RunHiddenScript(TrustScript, 'trust.ps1', True);

			// Step 5: install, then resolve the Start Menu AppID so the
			// "Launch FluentFlyout" checkbox on the Finish page works. MSIX
			// apps don't have a fixed .exe path to launch directly, so we
			// look up their shell:appsFolder identity via Get-StartApps.
			ProgressPage.SetText('Installing FluentFlyout...', '');
			ProgressPage.SetProgress(4, 4);
			InstallScript :=
				'$ErrorActionPreference = ''Stop''' + #13#10 +
				'Add-AppxPackage -Path ''' + MsixPath + '''' + #13#10 +
				'$appId = Get-StartApps | Where-Object { $_.Name -like ''*FluentFlyout*'' } | Select-Object -First 1 -ExpandProperty AppID' + #13#10 +
				'if ($appId) { Set-Content -Path ''' + AppIdPath + ''' -Value $appId -NoNewline }';
			RunHiddenScript(InstallScript, 'install.ps1', True);

			if LoadStringFromFile(AppIdPath, AppIdAnsi) then
				AppLaunchID := String(AppIdAnsi)
			else
				AppLaunchID := '';

			// Step 6: clean up
			ProgressPage.SetText('Cleaning up...', '');
			CleanupScript :=
				'Remove-Item ''' + TempDir + '\signing.cer'', ''' + MsixPath + ''', ''' +
				AppIdPath + ''', ''' + SizePath + ''', ''' + DoneMarkerPath + ''' -Force -ErrorAction SilentlyContinue';
			RunHiddenScript(CleanupScript, 'cleanup.ps1', True);
		finally
			ProgressPage.Hide;
		end;
	end;
end;
