; Windows 安装向导。由 package_windows_installer.py 传入本次已校验的资源目录和版本。
#ifndef PayloadDir
  #error PayloadDir is required
#endif
#ifndef Release
  #error Release is required
#endif
#ifndef OutputDir
  #error OutputDir is required
#endif

[Setup]
AppId={{F2E2A735-C912-4CCE-ABF0-74F70628F3CB}
AppName=共生连线
AppVersion={#Release}
AppVerName=共生连线
AppPublisher=共生连线
DefaultDirName={localappdata}\Programs\ConjoinedTwins
DefaultGroupName=共生连线
DisableProgramGroupPage=yes
DisableWelcomePage=no
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
MinVersion=10.0
OutputDir={#OutputDir}
OutputBaseFilename=ConjoinedTwins-Setup-{#Release}
Compression=lzma2/fast
SolidCompression=yes
WizardStyle=modern
UninstallDisplayName=共生连线
UninstallDisplayIcon={app}\ConjoinedTwins.exe
CloseApplications=no
RestartApplications=no
SetupLogging=yes

[Languages]
Name: "chinesesimp"; MessagesFile: "installer\ChineseSimplified.isl"

[Messages]
WelcomeLabel2=欢迎安装共生连线。%n%n安装后，双击桌面的“共生连线”即可开始游戏。游戏启动时会自动检查更新。%n%n联机游玩需要主机的联机服务在线。
FinishedLabel=共生连线已安装完成。%n%n以后可以从桌面或开始菜单启动游戏。

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "快捷方式："

[Files]
Source: "{#PayloadDir}\ConjoinedTwins.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#PayloadDir}\ConjoinedTwins.pck"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#PayloadDir}\packs.json"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#PayloadDir}\packs\*.pck"; DestDir: "{app}\packs"; Flags: ignoreversion
Source: "{#PayloadDir}\安装说明.txt"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\共生连线\共生连线"; Filename: "{app}\ConjoinedTwins.exe"; WorkingDir: "{app}"
Name: "{autoprograms}\共生连线\卸载共生连线"; Filename: "{uninstallexe}"
Name: "{autodesktop}\共生连线"; Filename: "{app}\ConjoinedTwins.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\ConjoinedTwins.exe"; Description: "启动共生连线"; WorkingDir: "{app}"; Flags: nowait postinstall skipifsilent
