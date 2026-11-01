[Setup]
AppId={{APP_ID}}
AppVersion={{APP_VERSION}}
AppName={cm:AppDisplayName}
AppPublisher={{PUBLISHER_NAME}}
DefaultDirName={autopf}\Reveric
DisableProgramGroupPage=yes
OutputDir=.
OutputBaseFilename={{OUTPUT_BASE_FILENAME}}
Compression=lzma
SolidCompression=yes
SetupLogging=yes
SetupIconFile={{SETUP_ICON_FILE}}
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64

[Languages]
{% for locale in LOCALES %}
{% if locale == 'en' %}Name: "english"; MessagesFile: "compiler:Default.isl"{% endif %}
{% if locale == 'hy' %}Name: "armenian"; MessagesFile: "compiler:Languages\\Armenian.isl"{% endif %}
{% if locale == 'bg' %}Name: "bulgarian"; MessagesFile: "compiler:Languages\\Bulgarian.isl"{% endif %}
{% if locale == 'ca' %}Name: "catalan"; MessagesFile: "compiler:Languages\\Catalan.isl"{% endif %}
{% if locale == 'zh' %}Name: "chinesesimplified"; MessagesFile: "compiler:Languages\\ChineseSimplified.isl"{% endif %}
{% if locale == 'co' %}Name: "corsican"; MessagesFile: "compiler:Languages\\Corsican.isl"{% endif %}
{% if locale == 'cs' %}Name: "czech"; MessagesFile: "compiler:Languages\\Czech.isl"{% endif %}
{% if locale == 'da' %}Name: "danish"; MessagesFile: "compiler:Languages\\Danish.isl"{% endif %}
{% if locale == 'nl' %}Name: "dutch"; MessagesFile: "compiler:Languages\\Dutch.isl"{% endif %}
{% if locale == 'fi' %}Name: "finnish"; MessagesFile: "compiler:Languages\\Finnish.isl"{% endif %}
{% if locale == 'fr' %}Name: "french"; MessagesFile: "compiler:Languages\\French.isl"{% endif %}
{% if locale == 'de' %}Name: "german"; MessagesFile: "compiler:Languages\\German.isl"{% endif %}
{% if locale == 'he' %}Name: "hebrew"; MessagesFile: "compiler:Languages\\Hebrew.isl"{% endif %}
{% if locale == 'is' %}Name: "icelandic"; MessagesFile: "compiler:Languages\\Icelandic.isl"{% endif %}
{% if locale == 'it' %}Name: "italian"; MessagesFile: "compiler:Languages\\Italian.isl"{% endif %}
{% if locale == 'ja' %}Name: "japanese"; MessagesFile: "compiler:Languages\\Japanese.isl"{% endif %}
{% if locale == 'no' %}Name: "norwegian"; MessagesFile: "compiler:Languages\\Norwegian.isl"{% endif %}
{% if locale == 'pl' %}Name: "polish"; MessagesFile: "compiler:Languages\\Polish.isl"{% endif %}
{% if locale == 'pt' %}Name: "portuguese"; MessagesFile: "compiler:Languages\\Portuguese.isl"{% endif %}
{% if locale == 'ru' %}Name: "russian"; MessagesFile: "compiler:Languages\\Russian.isl"{% endif %}
{% if locale == 'sk' %}Name: "slovak"; MessagesFile: "compiler:Languages\\Slovak.isl"{% endif %}
{% if locale == 'sl' %}Name: "slovenian"; MessagesFile: "compiler:Languages\\Slovenian.isl"{% endif %}
{% if locale == 'es' %}Name: "spanish"; MessagesFile: "compiler:Languages\\Spanish.isl"{% endif %}
{% if locale == 'tr' %}Name: "turkish"; MessagesFile: "compiler:Languages\\Turkish.isl"{% endif %}
{% if locale == 'uk' %}Name: "ukrainian"; MessagesFile: "compiler:Languages\\Ukrainian.isl"{% endif %}
{% endfor %}

[CustomMessages]
AppDisplayName=Reveric
chinesesimplified.AppDisplayName=幻界
LaunchApp=Launch Reveric
chinesesimplified.LaunchApp=启动 幻界
AutoStartApp=Start Reveric when Windows starts
chinesesimplified.AutoStartApp=Windows 启动时自动启动 幻界
PreparingRuntime=Checking and installing Microsoft Visual C++ runtime...
chinesesimplified.PreparingRuntime=正在检查并安装 Microsoft Visual C++ 运行库…
RuntimeFailed=Microsoft Visual C++ runtime could not be installed or verified. Restart Windows and try again. If this continues, send the following log files to support:
chinesesimplified.RuntimeFailed=Microsoft Visual C++ 运行库安装或检查失败。请重启 Windows 后重试；如果仍然失败，请将以下日志文件发送给客服：
RuntimeRepairNewer=A newer Microsoft Visual C++ runtime is installed, but required DLL files are missing or unreadable. Open Windows Settings > Apps, repair Microsoft Visual C++ Redistributable (x64), then run this installer again.
chinesesimplified.RuntimeRepairNewer=电脑已安装更高版本的 Microsoft Visual C++ 运行库，但必要的 DLL 文件缺失或无法读取。请在 Windows 设置的应用列表中修复 Microsoft Visual C++ Redistributable (x64)，然后重新运行本安装程序。
RuntimeRestart=Microsoft Visual C++ runtime requires a restart. Restart Windows, then run this installer again to finish installing Reveric.
chinesesimplified.RuntimeRestart=Microsoft Visual C++ 运行库需要重启才能完成配置。请重启 Windows，然后重新运行本安装程序以完成幻界的安装。

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "launchAtStartup"; Description: "{cm:AutoStartApp}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: {% if LAUNCH_AT_STARTUP != true %}unchecked{% else %}checkedonce{% endif %}

[Files]
; .iss 渲染到 dist/<ver>/<name>.iss，故相对路径回到仓库根再进 windows\packaging\exe
; 放在 solid archive 最前面，安装前提取时无需先解压整个应用。
Source: "..\..\windows\packaging\exe\vc_redist.x64.exe"; Flags: dontcopy
Source: "{{SOURCE_DIR}}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\\Reveric"; Filename: "{app}\\{{EXECUTABLE_NAME}}"
Name: "{autodesktop}\\Reveric"; Filename: "{app}\\{{EXECUTABLE_NAME}}"; Tasks: desktopicon
Name: "{userstartup}\\Reveric"; Filename: "{app}\\{{EXECUTABLE_NAME}}"; WorkingDir: "{app}"; Tasks: launchAtStartup

[Run]
Filename: "{app}\\{{EXECUTABLE_NAME}}"; Description: "{cm:LaunchApp}"; Flags: nowait postinstall skipifsilent

[Code]
const
  RuntimeKey = 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64';

var
  RuntimeRestartPending: Boolean;
  DesktopTaskDefaultApplied: Boolean;

function InstalledRuntimeVersion(var Version: Int64): Boolean;
var
  Installed: Cardinal;
  VersionText: String;
begin
  Result := False;
  if not RegQueryDWordValue(HKLM64, RuntimeKey, 'Installed', Installed) then
    Exit;
  if Installed <> 1 then
    Exit;
  if not RegQueryStringValue(HKLM64, RuntimeKey, 'Version', VersionText) then
    Exit;
  if Copy(VersionText, 1, 1) = 'v' then
    Delete(VersionText, 1, 1);
  Result := StrToVersion(VersionText, Version);
end;

function RuntimeDllAvailable(const Name: String): Boolean;
var
  Version: Int64;
begin
  Result := GetPackedVersion(ExpandConstant('{sys}\') + Name, Version);
  if not Result then
    Log('Missing or unreadable x64 runtime DLL: ' + Name);
end;

function RuntimeFilesAvailable: Boolean;
begin
  { Use the native system directory in this x64 installer. Individual DLL patch
    versions may differ, so use the registered package version for comparison. }
  Result := RuntimeDllAvailable('vcruntime140.dll') and
    RuntimeDllAvailable('vcruntime140_1.dll') and
    RuntimeDllAvailable('msvcp140.dll');
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  BundledVersion, InstalledVersion: Int64;
  HasInstalledRuntime: Boolean;
  RuntimePath, RuntimeLog, Action: String;
  ResultCode: Integer;
begin
  Result := '';
  NeedsRestart := RuntimeRestartPending;
  if RuntimeRestartPending then begin
    Result := CustomMessage('RuntimeRestart');
    Exit;
  end;

  { Keep logs outside Setup's temporary directory, which is removed on exit. }
  RuntimeLog := ExpandConstant('{commonappdata}\{{APP_ID}}\InstallerLogs');
  if not ForceDirectories(RuntimeLog) then begin
    Result := CustomMessage('RuntimeFailed') + #13#10 + ExpandConstant('{log}');
    Exit;
  end;
  RuntimeLog := RuntimeLog + '\vc-redist-' +
    GetDateTimeString('yyyymmdd-hhnnss', '-', ':') + '.log';
  try
    ExtractTemporaryFile('vc_redist.x64.exe');
    RuntimePath := ExpandConstant('{tmp}\vc_redist.x64.exe');
    if not GetPackedVersion(RuntimePath, BundledVersion) then
      RaiseException('Cannot read bundled VC++ runtime version');
    Log('Bundled VC++ runtime: ' + VersionToStr(BundledVersion));
    HasInstalledRuntime := InstalledRuntimeVersion(InstalledVersion);
    Action := '/install';
    if HasInstalledRuntime then begin
      Log('Installed VC++ runtime: ' + VersionToStr(InstalledVersion));
      if ComparePackedVersion(InstalledVersion, BundledVersion) >= 0 then begin
        if RuntimeFilesAvailable then
          Exit;
        if ComparePackedVersion(InstalledVersion, BundledVersion) > 0 then begin
          Result := CustomMessage('RuntimeRepairNewer');
          Exit;
        end;
        Action := '/repair';
      end;
    end;

    WizardForm.PreparingLabel.Caption := CustomMessage('PreparingRuntime');
    Log('VC++ runtime action: ' + Action + '; log: ' + RuntimeLog);
    if not Exec(RuntimePath, Action + ' /quiet /norestart /log "' +
      RuntimeLog + '"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
      RaiseException('Cannot start VC++ runtime installer: ' + IntToStr(ResultCode));
    Log('VC++ runtime installer exit code: ' + IntToStr(ResultCode));
    if (ResultCode = 3010) or (ResultCode = 1641) then begin
      RuntimeRestartPending := True;
      NeedsRestart := True;
      Result := CustomMessage('RuntimeRestart');
      Exit;
    end;
    if ResultCode <> 0 then
      RaiseException('VC++ runtime installer failed: ' + IntToStr(ResultCode));
    if not InstalledRuntimeVersion(InstalledVersion) then
      RaiseException('VC++ runtime registration missing after installation');
    if (ComparePackedVersion(InstalledVersion, BundledVersion) < 0) or
      not RuntimeFilesAvailable then
      RaiseException('VC++ runtime verification failed after installation');
  except
    Log(GetExceptionMessage);
    Result := CustomMessage('RuntimeFailed') + #13#10 +
      ExpandConstant('{log}') + #13#10 + RuntimeLog;
  end;
end;

// Upgrades restore the previous task selection; keep the desktop shortcut
// checked on first entry, then preserve the user's choices when navigating back.
procedure CurPageChanged(CurPageID: Integer);
begin
  if (CurPageID = wpSelectTasks) and not DesktopTaskDefaultApplied then begin
    WizardSelectTasks('desktopicon');
    DesktopTaskDefaultApplied := True;
  end;
end;
