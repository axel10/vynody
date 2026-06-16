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
  end;
end;
