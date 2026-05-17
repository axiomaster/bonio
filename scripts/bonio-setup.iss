; Bonio Windows Installer Script (InnoSetup 6)
; Usage: ISCC.exe scripts\bonio-setup.iss /DAppVersion=0.1.0
; Note: Paths are relative to this script's directory (scripts/)

#ifndef AppVersion
  #define AppVersion "0.1.0"
#endif

#define AppName "Bonio"
#define AppPublisher "Bonio"
#define AppURL "https://github.com/axiomaster/bonio"
#define AppExeName "bonio_desktop.exe"
#define BuildRoot "..\desktop\build\windows\x64\runner\Release"

[Setup]
AppId={{B8E3F1A2-9C4D-4F6E-A7B8-1C2D3E4F5A6B}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
AllowNoIcons=yes
OutputDir=..\release\v{#AppVersion}
OutputBaseFilename=Bonio-v{#AppVersion}-windows-x64-setup
SetupIconFile=..\desktop\assets\app_icon.ico
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\{#AppExeName}
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
; Main executable
Source: "{#BuildRoot}\bonio_desktop.exe"; DestDir: "{app}"; Flags: ignoreversion
; Server
Source: "{#BuildRoot}\hiclaw.exe"; DestDir: "{app}"; Flags: ignoreversion
; DLLs
Source: "{#BuildRoot}\*.dll"; DestDir: "{app}"; Flags: ignoreversion
; Data directory
Source: "{#BuildRoot}\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs
; Assets directory
Source: "{#BuildRoot}\assets\*"; DestDir: "{app}\assets"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{group}\{cm:UninstallProgram,{#AppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
