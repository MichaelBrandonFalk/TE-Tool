#define MyAppName "TE Tool"
#ifndef MyAppVersion
#define MyAppVersion "11.12"
#endif
#define MyAppPublisher "Great American Media"
#define MyAppExeName "te-tool.exe"
#ifndef MyAppSourceDir
#define MyAppSourceDir "..\..\dist\te-tool"
#endif
#ifndef MyAppIcon
#define MyAppIcon "..\..\build\assets\te-tool.ico"
#endif
#ifndef MyOutputDir
#define MyOutputDir "..\..\release"
#endif

[Setup]
AppId={{E0BA829A-7E57-4E6D-8982-9378F4A5C138}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\TE Tool
DefaultGroupName=TE Tool
DisableProgramGroupPage=yes
OutputDir={#MyOutputDir}
OutputBaseFilename=TE-Tool-Version-{#MyAppVersion}-Windows-x64-Setup
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
SetupIconFile={#MyAppIcon}
UninstallDisplayIcon={app}\{#MyAppExeName}
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"; Flags: unchecked

[Files]
Source: "{#MyAppSourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\TE Tool"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\TE Tool"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch TE Tool"; Flags: nowait postinstall skipifsilent
