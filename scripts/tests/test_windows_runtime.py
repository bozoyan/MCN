"""Execute the installer's actual Pascal code with simulated Windows APIs.

Run: python3 -m unittest discover -s scripts/tests -p test_windows_runtime.py -v
Requires Free Pascal (fpc). This is not a Windows/Inno Setup integration test.
"""

from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]

STUBS = r"""
program RuntimeTests;
{$mode delphi}{$H+}
uses SysUtils;
const HKLM64 = 64; SW_HIDE = 0; ewWaitUntilTerminated = 1;
  wpSelectDir = 6; wpSelectTasks = 9; wpReady = 10;
type
  TLabel = record Caption: String; end;
  TWizard = record PreparingLabel: TLabel; end;
var
  WizardForm: TWizard;
  Registered, FilesReady, LaunchOK, InstallWorks, BundleValid: Boolean;
  ExtractOK, DirectoryOK: Boolean;
  InstalledFlag: Cardinal;
  VersionText, MissingDll, LastParams: String;
  ExitCode, ExecCount: Integer;
  DesktopIconSelected: Boolean;

procedure Check(Condition: Boolean; const Message: String);
begin
  if not Condition then raise Exception.Create(Message);
end;

procedure Log(const Message: String);
begin end;

procedure WizardSelectTasks(const Tasks: String);
begin
  Check(Tasks = 'desktopicon', 'Only the desktop shortcut default should change');
  DesktopIconSelected := True;
end;

function CustomMessage(const Name: String): String;
begin Result := Name; end;

function ExpandConstant(const Value: String): String;
begin Result := Value; end;

function ForceDirectories(const Path: String): Boolean;
begin Result := DirectoryOK; end;

function GetDateTimeString(const Format, DateSeparator, TimeSeparator: String): String;
begin Result := '20260918-120000'; end;

procedure RaiseException(const Message: String);
begin raise Exception.Create(Message); end;

function GetExceptionMessage: String;
begin Result := Exception(ExceptObject).Message; end;

function RegQueryDWordValue(Root: Integer; const Key, Name: String;
  var Value: Cardinal): Boolean;
begin
  Check(Root = HKLM64, 'Must inspect x64 registry');
  Check(Name = 'Installed', 'Must inspect installation status');
  Value := InstalledFlag;
  Result := Registered;
end;

function RegQueryStringValue(Root: Integer; const Key, Name: String;
  var Value: String): Boolean;
begin
  Check(Root = HKLM64, 'Must inspect x64 registry');
  Value := VersionText;
  Result := Registered;
end;

function StrToVersion(Text: String; var Version: Int64): Boolean;
var Index, Dot, Part: Integer; Token: String;
begin
  Result := False;
  Version := 0;
  for Index := 1 to 4 do begin
    Dot := Pos('.', Text);
    if Dot = 0 then begin Token := Text; Text := ''; end
    else begin Token := Copy(Text, 1, Dot - 1); Delete(Text, 1, Dot); end;
    if not TryStrToInt(Token, Part) then Exit;
    if (Part < 0) or (Part > 65535) then Exit;
    Version := (Version shl 16) or Part;
  end;
  Result := Text = '';
end;

function ComparePackedVersion(A, B: Int64): Integer;
begin
  if A < B then Result := -1
  else if A > B then Result := 1 else Result := 0;
end;

function VersionToStr(Version: Int64): String;
begin Result := IntToStr(Version); end;

function GetPackedVersion(const Path: String; var Version: Int64): Boolean;
begin
  StrToVersion('14.44.35211.0', Version);
  if Pos('vc_redist.x64.exe', Path) > 0 then Result := BundleValid
  else begin
    Check(Pos('{sys}\', Path) = 1, 'Must inspect native system DLLs');
    Result := FilesReady or (Pos(MissingDll, Path) = 0);
  end;
end;

procedure ExtractTemporaryFile(const Name: String);
begin
  if not ExtractOK then raise Exception.Create('Extraction failed');
end;

function Exec(const Path, Params, WorkingDir: String; ShowCmd, Wait: Integer;
  var ResultCode: Integer): Boolean;
begin
  Check(Wait = ewWaitUntilTerminated, 'Must wait for runtime installer');
  Check(Pos('/quiet /norestart /log "', Params) > 0, 'Must suppress reboot and log');
  Check(Pos('{commonappdata}', Params) > 0, 'Logs must survive installer exit');
  Inc(ExecCount);
  LastParams := Params;
  Result := LaunchOK;
  ResultCode := ExitCode;
  if LaunchOK and (ExitCode = 0) and InstallWorks then begin
    Registered := True;
    InstalledFlag := 1;
    VersionText := 'v14.44.35211.0';
    FilesReady := True;
  end;
end;
"""

DRIVER = r"""
var
  Scenario, Error: String;
  Restart: Boolean;
begin
  Scenario := ParamStr(1);
  if Scenario = 'desktop_task_navigation' then begin
    DesktopIconSelected := False;
    CurPageChanged(wpSelectDir);
    Check(not DesktopIconSelected, 'Do not change tasks before the task page');
    CurPageChanged(wpSelectTasks);
    Check(DesktopIconSelected, 'Default to a desktop shortcut on first entry');
    DesktopIconSelected := False;
    CurPageChanged(wpReady);
    CurPageChanged(wpSelectTasks);
    Check(not DesktopIconSelected, 'Back from Ready must preserve user opt-out');
    CurPageChanged(wpSelectDir);
    CurPageChanged(wpSelectTasks);
    Check(not DesktopIconSelected, 'Returning from directory must preserve opt-out');
    WriteLn('PASS ', Scenario);
    Halt(0);
  end;
  Registered := True; InstalledFlag := 1; FilesReady := True;
  LaunchOK := True; InstallWorks := True; BundleValid := True;
  ExtractOK := True; DirectoryOK := True;
  VersionText := 'v14.44.35211.0'; MissingDll := 'vcruntime140_1.dll';
  ExitCode := 0; ExecCount := 0; Restart := False;
  if Scenario = 'absent' then begin Registered := False; FilesReady := False; end;
  if Scenario = 'old' then VersionText := 'v14.9.0.0';
  if Scenario = 'disabled' then InstalledFlag := 0;
  if Scenario = 'invalid_version' then VersionText := 'invalid';
  if Scenario = 'newer' then VersionText := 'v14.50.0.0';
  if Pos('repair_', Scenario) = 1 then begin
    FilesReady := False;
    MissingDll := Copy(Scenario, 8, Length(Scenario));
  end;
  if Scenario = 'newer_broken' then begin
    VersionText := 'v14.50.0.0'; FilesReady := False;
  end;
  if Scenario = 'bad_bundle' then BundleValid := False;
  if Scenario = 'extract_failure' then ExtractOK := False;
  if Scenario = 'log_failure' then DirectoryOK := False;
  if Scenario = 'failed_exit' then begin Registered := False; ExitCode := 1603; end;
  if Scenario = 'newer_exit' then begin Registered := False; ExitCode := 1638; end;
  if Scenario = 'launch_failure' then begin Registered := False; LaunchOK := False; end;
  if Scenario = 'false_success' then begin Registered := False; InstallWorks := False; end;
  if Scenario = 'still_broken' then begin FilesReady := False; InstallWorks := False; end;
  if Scenario = 'restart_3010' then begin Registered := False; ExitCode := 3010; end;
  if Scenario = 'restart_1641' then begin Registered := False; ExitCode := 1641; end;

  Error := PrepareToInstall(Restart);
  if Pos('restart_', Scenario) = 1 then begin
    Check(Restart and (Error = 'RuntimeRestart'), 'Restart must block installation');
    Check(ExecCount = 1, 'Runtime installer should run once');
    Error := PrepareToInstall(Restart);
    Check(Restart and (Error = 'RuntimeRestart') and (ExecCount = 1),
      'Retry must not bypass a pending reboot');
  end else if Scenario = 'newer_broken' then begin
    Check((Error = 'RuntimeRepairNewer') and (ExecCount = 0),
      'Never repair a newer runtime with an older bundle');
  end else if (Scenario = 'bad_bundle') or (Scenario = 'failed_exit') or
    (Scenario = 'newer_exit') or (Scenario = 'launch_failure') or
    (Scenario = 'false_success') or (Scenario = 'still_broken') or
    (Scenario = 'extract_failure') or (Scenario = 'log_failure') then begin
    Check(Pos('RuntimeFailed', Error) = 1, 'Failure must block installation');
    Check(Pos('{log}', Error) > 0, 'Failure must identify setup log');
    Check(not Restart, 'Failure must not report successful reboot requirement');
  end else begin
    Check((Error = '') and not Restart, 'Healthy runtime must allow installation');
    if (Scenario = 'healthy') or (Scenario = 'newer') then
      Check(ExecCount = 0, 'Healthy runtime must not be reinstalled')
    else begin
      Check(ExecCount = 1, 'Missing/broken runtime must run prerequisite');
      if Pos('repair_', Scenario) = 1 then
        Check(Pos('/repair ', LastParams) = 1, 'Same-version damage needs repair')
      else Check(Pos('/install ', LastParams) = 1, 'Missing/old runtime needs install');
    end;
  end;
  WriteLn('PASS ', Scenario);
end.
"""


class WindowsRuntimeTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not shutil.which("fpc"):
            raise RuntimeError("Install Free Pascal (fpc) to run these tests")
        cls.temp = tempfile.TemporaryDirectory(prefix="reveric-runtime-test-")
        cls.addClassCleanup(cls.temp.cleanup)
        directory = Path(cls.temp.name)
        installer = ROOT / "windows/packaging/exe/inno_setup.iss"
        code = installer.read_text().split("[Code]\n", 1)[1]
        source = directory / "runtime_test.pas"
        source.write_text(STUBS + code + DRIVER)
        result = subprocess.run(
            ["fpc", str(source)], cwd=directory, capture_output=True, text=True,
            timeout=30,
        )
        if result.returncode:
            raise RuntimeError(result.stdout + result.stderr)
        cls.binary = directory / "runtime_test"

    def test_desktop_task_navigation_preserves_opt_out(self):
        result = subprocess.run(
            [str(self.binary), "desktop_task_navigation"],
            capture_output=True, text=True, timeout=5,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS desktop_task_navigation", result.stdout)

    def test_prerequisite_scenarios(self):
        scenarios = [
            "absent", "old", "disabled", "invalid_version", "healthy", "newer",
            "repair_vcruntime140.dll", "repair_vcruntime140_1.dll",
            "repair_msvcp140.dll", "newer_broken", "bad_bundle", "failed_exit",
            "newer_exit", "launch_failure", "false_success", "still_broken",
            "extract_failure", "log_failure", "restart_3010", "restart_1641",
        ]
        for scenario in scenarios:
            with self.subTest(scenario=scenario):
                result = subprocess.run(
                    [str(self.binary), scenario], capture_output=True, text=True,
                    timeout=5,
                )
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn(f"PASS {scenario}", result.stdout)


if __name__ == "__main__":
    unittest.main()
