#define MyAppName "Vynody"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "Vynody"
#define MyAppURL "https://github.com"
#define MyAppExeName "Vynody.exe"
#define MyAppId "app.vynody.player"
#define MyAppDataDirName "Vynody"
#define MyAppLegacyDataDirName "vibe_flow"

#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif

#ifndef OutputDir
  #define OutputDir "..\..\build\windows\installer"
#endif

[Setup]
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir={#OutputDir}
OutputBaseFilename=vynody-windows-setup
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
ChangesAssociations=yes

[Registry]
; Register the ProgID for Vynody Audio File
Root: HKA; Subkey: "Software\Classes\Vynody.AssocFile"; ValueType: string; ValueName: ""; ValueData: "Vynody Audio File"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\Vynody.AssocFile\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#MyAppExeName},0"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\Vynody.AssocFile\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyAppExeName}"" ""%1"""; Flags: uninsdeletekey

; Register application capabilities for Default Apps UI
Root: HKA; Subkey: "Software\Vynody\Capabilities"; ValueType: string; ValueName: "ApplicationName"; ValueData: "Vynody"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Vynody\Capabilities"; ValueType: string; ValueName: "ApplicationDescription"; ValueData: "A fully functional, highly compatible, and robust cross-platform music player."; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\RegisteredApplications"; ValueType: string; ValueName: "Vynody"; ValueData: "Software\Vynody\Capabilities"; Flags: uninsdeletevalue

; Associate capabilities and register OpenWithProgids for all supported audio formats
Root: HKA; Subkey: "Software\Vynody\Capabilities\FileAssociations"; ValueType: string; ValueName: ".aac"; ValueData: "Vynody.AssocFile"; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.aac\OpenWithProgids"; ValueType: string; ValueName: "Vynody.AssocFile"; ValueData: ""; Flags: uninsdeletevalue

Root: HKA; Subkey: "Software\Vynody\Capabilities\FileAssociations"; ValueType: string; ValueName: ".aif"; ValueData: "Vynody.AssocFile"; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.aif\OpenWithProgids"; ValueType: string; ValueName: "Vynody.AssocFile"; ValueData: ""; Flags: uninsdeletevalue

Root: HKA; Subkey: "Software\Vynody\Capabilities\FileAssociations"; ValueType: string; ValueName: ".aiff"; ValueData: "Vynody.AssocFile"; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.aiff\OpenWithProgids"; ValueType: string; ValueName: "Vynody.AssocFile"; ValueData: ""; Flags: uninsdeletevalue

Root: HKA; Subkey: "Software\Vynody\Capabilities\FileAssociations"; ValueType: string; ValueName: ".alac"; ValueData: "Vynody.AssocFile"; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.alac\OpenWithProgids"; ValueType: string; ValueName: "Vynody.AssocFile"; ValueData: ""; Flags: uninsdeletevalue

Root: HKA; Subkey: "Software\Vynody\Capabilities\FileAssociations"; ValueType: string; ValueName: ".caf"; ValueData: "Vynody.AssocFile"; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.caf\OpenWithProgids"; ValueType: string; ValueName: "Vynody.AssocFile"; ValueData: ""; Flags: uninsdeletevalue

Root: HKA; Subkey: "Software\Vynody\Capabilities\FileAssociations"; ValueType: string; ValueName: ".flac"; ValueData: "Vynody.AssocFile"; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.flac\OpenWithProgids"; ValueType: string; ValueName: "Vynody.AssocFile"; ValueData: ""; Flags: uninsdeletevalue

Root: HKA; Subkey: "Software\Vynody\Capabilities\FileAssociations"; ValueType: string; ValueName: ".m4a"; ValueData: "Vynody.AssocFile"; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.m4a\OpenWithProgids"; ValueType: string; ValueName: "Vynody.AssocFile"; ValueData: ""; Flags: uninsdeletevalue

Root: HKA; Subkey: "Software\Vynody\Capabilities\FileAssociations"; ValueType: string; ValueName: ".m4b"; ValueData: "Vynody.AssocFile"; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.m4b\OpenWithProgids"; ValueType: string; ValueName: "Vynody.AssocFile"; ValueData: ""; Flags: uninsdeletevalue

Root: HKA; Subkey: "Software\Vynody\Capabilities\FileAssociations"; ValueType: string; ValueName: ".m4p"; ValueData: "Vynody.AssocFile"; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.m4p\OpenWithProgids"; ValueType: string; ValueName: "Vynody.AssocFile"; ValueData: ""; Flags: uninsdeletevalue

Root: HKA; Subkey: "Software\Vynody\Capabilities\FileAssociations"; ValueType: string; ValueName: ".mid"; ValueData: "Vynody.AssocFile"; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.mid\OpenWithProgids"; ValueType: string; ValueName: "Vynody.AssocFile"; ValueData: ""; Flags: uninsdeletevalue

Root: HKA; Subkey: "Software\Vynody\Capabilities\FileAssociations"; ValueType: string; ValueName: ".midi"; ValueData: "Vynody.AssocFile"; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.midi\OpenWithProgids"; ValueType: string; ValueName: "Vynody.AssocFile"; ValueData: ""; Flags: uninsdeletevalue

Root: HKA; Subkey: "Software\Vynody\Capabilities\FileAssociations"; ValueType: string; ValueName: ".mp3"; ValueData: "Vynody.AssocFile"; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.mp3\OpenWithProgids"; ValueType: string; ValueName: "Vynody.AssocFile"; ValueData: ""; Flags: uninsdeletevalue

Root: HKA; Subkey: "Software\Vynody\Capabilities\FileAssociations"; ValueType: string; ValueName: ".ogg"; ValueData: "Vynody.AssocFile"; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.ogg\OpenWithProgids"; ValueType: string; ValueName: "Vynody.AssocFile"; ValueData: ""; Flags: uninsdeletevalue

Root: HKA; Subkey: "Software\Vynody\Capabilities\FileAssociations"; ValueType: string; ValueName: ".opus"; ValueData: "Vynody.AssocFile"; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.opus\OpenWithProgids"; ValueType: string; ValueName: "Vynody.AssocFile"; ValueData: ""; Flags: uninsdeletevalue

Root: HKA; Subkey: "Software\Vynody\Capabilities\FileAssociations"; ValueType: string; ValueName: ".wav"; ValueData: "Vynody.AssocFile"; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.wav\OpenWithProgids"; ValueType: string; ValueName: "Vynody.AssocFile"; ValueData: ""; Flags: uninsdeletevalue

Root: HKA; Subkey: "Software\Vynody\Capabilities\FileAssociations"; ValueType: string; ValueName: ".webm"; ValueData: "Vynody.AssocFile"; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.webm\OpenWithProgids"; ValueType: string; ValueName: "Vynody.AssocFile"; ValueData: ""; Flags: uninsdeletevalue

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[Code]
procedure DeleteUserDataIfExists(const DataDir: string);
begin
  if DirExists(DataDir) then
  begin
    DelTree(DataDir, True, True, True);
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then
  begin
    if MsgBox(
      'Remove Vynody user data as well?' + #13#10 + #13#10 +
      'This will delete local settings, caches, logs, and databases stored in AppData.',
      mbConfirmation, MB_YESNO) = IDYES then
    begin
      DeleteUserDataIfExists(ExpandConstant('{userappdata}\{#MyAppDataDirName}'));
      DeleteUserDataIfExists(ExpandConstant('{userlocalappdata}\{#MyAppDataDirName}'));
      DeleteUserDataIfExists(ExpandConstant('{userappdata}\{#MyAppLegacyDataDirName}'));
      DeleteUserDataIfExists(ExpandConstant('{userlocalappdata}\{#MyAppLegacyDataDirName}'));
      DeleteUserDataIfExists(ExpandConstant('{userappdata}\{#MyAppPublisher}\{#MyAppDataDirName}'));
      DeleteUserDataIfExists(ExpandConstant('{userlocalappdata}\{#MyAppPublisher}\{#MyAppDataDirName}'));
      DeleteUserDataIfExists(ExpandConstant('{userappdata}\{#MyAppId}'));
      DeleteUserDataIfExists(ExpandConstant('{userlocalappdata}\{#MyAppId}'));
    end;

    // Clean up legacy custom registry settings written by older app versions to HKCU
    if RegKeyExists(HKEY_CURRENT_USER, 'Software\Classes\Vynody.AssocFile') then
    begin
      RegDeleteKeyIncludingSubkeys(HKEY_CURRENT_USER, 'Software\Classes\Vynody.AssocFile');
    end;
    if RegKeyExists(HKEY_CURRENT_USER, 'Software\Vynody') then
    begin
      RegDeleteKeyIncludingSubkeys(HKEY_CURRENT_USER, 'Software\Vynody');
    end;
    RegDeleteValue(HKEY_CURRENT_USER, 'Software\RegisteredApplications', 'Vynody');

    // De-associate OpenWithProgids written to HKCU
    RegDeleteValue(HKEY_CURRENT_USER, 'Software\Classes\.aac\OpenWithProgids', 'Vynody.AssocFile');
    RegDeleteValue(HKEY_CURRENT_USER, 'Software\Classes\.aif\OpenWithProgids', 'Vynody.AssocFile');
    RegDeleteValue(HKEY_CURRENT_USER, 'Software\Classes\.aiff\OpenWithProgids', 'Vynody.AssocFile');
    RegDeleteValue(HKEY_CURRENT_USER, 'Software\Classes\.alac\OpenWithProgids', 'Vynody.AssocFile');
    RegDeleteValue(HKEY_CURRENT_USER, 'Software\Classes\.caf\OpenWithProgids', 'Vynody.AssocFile');
    RegDeleteValue(HKEY_CURRENT_USER, 'Software\Classes\.flac\OpenWithProgids', 'Vynody.AssocFile');
    RegDeleteValue(HKEY_CURRENT_USER, 'Software\Classes\.m4a\OpenWithProgids', 'Vynody.AssocFile');
    RegDeleteValue(HKEY_CURRENT_USER, 'Software\Classes\.m4b\OpenWithProgids', 'Vynody.AssocFile');
    RegDeleteValue(HKEY_CURRENT_USER, 'Software\Classes\.m4p\OpenWithProgids', 'Vynody.AssocFile');
    RegDeleteValue(HKEY_CURRENT_USER, 'Software\Classes\.mid\OpenWithProgids', 'Vynody.AssocFile');
    RegDeleteValue(HKEY_CURRENT_USER, 'Software\Classes\.midi\OpenWithProgids', 'Vynody.AssocFile');
    RegDeleteValue(HKEY_CURRENT_USER, 'Software\Classes\.mp3\OpenWithProgids', 'Vynody.AssocFile');
    RegDeleteValue(HKEY_CURRENT_USER, 'Software\Classes\.ogg\OpenWithProgids', 'Vynody.AssocFile');
    RegDeleteValue(HKEY_CURRENT_USER, 'Software\Classes\.opus\OpenWithProgids', 'Vynody.AssocFile');
    RegDeleteValue(HKEY_CURRENT_USER, 'Software\Classes\.wav\OpenWithProgids', 'Vynody.AssocFile');
    RegDeleteValue(HKEY_CURRENT_USER, 'Software\Classes\.webm\OpenWithProgids', 'Vynody.AssocFile');
  end;
end;
