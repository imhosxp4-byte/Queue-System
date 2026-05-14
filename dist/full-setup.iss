[Setup]
AppName=ระบบคิว (Queue System)
AppVersion=1.0
AppPublisher=Hospital Queue System
AppId={{A3F2C1D0-4E5B-6F7A-8B9C-0D1E2F3A4B5C}
DefaultDirName={autopf}\QueueSystem
OutputDir=.
OutputBaseFilename=Queue-Setup-Full
SetupIconFile=
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
DisableProgramGroupPage=yes
PrivilegesRequired=admin
UninstallDisplayName=ระบบคิว (Queue System)
UninstallDisplayIcon={app}\QueueServer.exe
CloseApplications=no

[Languages]
Name: "thai"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "สร้าง Shortcut บน Desktop"; GroupDescription: "ตัวเลือกเพิ่มเติม:"; Flags: checkedonce
Name: "firewall"; Description: "เปิด Firewall อนุญาต Port 3000 (สำหรับเชื่อมต่อจากเครื่องอื่นใน LAN)"; GroupDescription: "ตัวเลือกเพิ่มเติม:"; Flags: checkedonce

[Files]
Source: "QueueServer.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "nssm.exe"; DestDir: "{app}\tools"; Flags: ignoreversion

[Dirs]
Name: "{app}\data"
Name: "{app}\logs"

[Icons]
Name: "{group}\เปิดระบบคิว (เบราว์เซอร์)"; Filename: "{app}\open-queue.url"
Name: "{group}\หยุด Queue System Service"; Filename: "{app}\tools\nssm.exe"; Parameters: "stop QueueSystem"; IconFilename: "{app}\QueueServer.exe"
Name: "{group}\ถอนการติดตั้ง"; Filename: "{uninstallexe}"
Name: "{commondesktop}\ระบบคิว"; Filename: "{app}\open-queue.url"; Tasks: desktopicon; Comment: "เปิดระบบคิวในเบราว์เซอร์"

[Code]

// ── ถอนการติดตั้งเวอร์ชันเก่าอัตโนมัติ ──────────────────────────────────
function GetOldUninstallString(): String;
var
  RegKey, UninstStr: String;
begin
  UninstStr := '';
  RegKey := 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{A3F2C1D0-4E5B-6F7A-8B9C-0D1E2F3A4B5C}_is1';
  if not RegQueryStringValue(HKLM, RegKey, 'UninstallString', UninstStr) then
    RegQueryStringValue(HKCU, RegKey, 'UninstallString', UninstStr);
  Result := UninstStr;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  UninstStr: String;
  ResultCode: Integer;
  NssmExe: String;
begin
  Result := '';

  // หยุด service เก่าก่อน (ถ้ามี)
  NssmExe := ExpandConstant('{autopf}') + '\QueueSystem\tools\nssm.exe';
  if FileExists(NssmExe) then
  begin
    Exec(NssmExe, 'stop QueueSystem', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Exec(NssmExe, 'remove QueueSystem confirm', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Sleep(1500);
  end;

  // ถอนการติดตั้งเวอร์ชันเก่า (silent)
  UninstStr := GetOldUninstallString();
  if UninstStr <> '' then
  begin
    UninstStr := RemoveQuotes(UninstStr);
    Exec(UninstStr, '/SILENT /NORESTART /SUPPRESSMSGBOXES', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Sleep(2000);
  end;
end;

// ── ตรวจสอบ service ──────────────────────────────────────────────────────
function ServiceExists(ServiceName: string): Boolean;
var
  ResultCode: Integer;
begin
  Exec(ExpandConstant('{app}\tools\nssm.exe'), 'status ' + ServiceName,
    '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Result := (ResultCode <> 3);
end;

// ── สร้าง URL shortcut ───────────────────────────────────────────────────
procedure CreateUrlShortcut();
var
  Lines: TStringList;
begin
  Lines := TStringList.Create;
  try
    Lines.Add('[InternetShortcut]');
    Lines.Add('URL=http://localhost:3000');
    Lines.Add('IconFile=' + ExpandConstant('{app}\QueueServer.exe'));
    Lines.Add('IconIndex=0');
    Lines.SaveToFile(ExpandConstant('{app}\open-queue.url'));
  finally
    Lines.Free;
  end;
end;

// ── หลังติดตั้งไฟล์เสร็จ ──────────────────────────────────────────────────
procedure CurStepChanged(CurStep: TSetupStep);
var
  AppDir, NssmExe: string;
  ResultCode: Integer;
begin
  if CurStep = ssPostInstall then
  begin
    AppDir  := ExpandConstant('{app}');
    NssmExe := AppDir + '\tools\nssm.exe';

    // สร้าง shortcut เบราว์เซอร์
    CreateUrlShortcut();

    // หยุด/ลบ service เก่าที่ยังค้างอยู่ (กรณี PrepareToInstall ไม่ครอบคลุม)
    if ServiceExists('QueueSystem') then
    begin
      Exec(NssmExe, 'stop QueueSystem', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
      Exec(NssmExe, 'remove QueueSystem confirm', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
      Sleep(1000);
    end;

    // ติดตั้ง service ใหม่
    Exec(NssmExe, 'install QueueSystem "' + AppDir + '\QueueServer.exe"',
      '', SW_HIDE, ewWaitUntilTerminated, ResultCode);

    // ตั้งค่า service
    Exec(NssmExe, 'set QueueSystem AppDirectory "' + AppDir + '"',
      '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Exec(NssmExe, 'set QueueSystem DisplayName "Queue Management System"',
      '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Exec(NssmExe, 'set QueueSystem Description "ระบบบริหารจัดการคิวโรงพยาบาล"',
      '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Exec(NssmExe, 'set QueueSystem Start SERVICE_AUTO_START',
      '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Exec(NssmExe, 'set QueueSystem AppStdout "' + AppDir + '\logs\service.log"',
      '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Exec(NssmExe, 'set QueueSystem AppStderr "' + AppDir + '\logs\error.log"',
      '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Exec(NssmExe, 'set QueueSystem AppRotateFiles 1',
      '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Exec(NssmExe, 'set QueueSystem AppRotateBytes 5242880',
      '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Exec(NssmExe, 'set QueueSystem AppExit Default Restart',
      '', SW_HIDE, ewWaitUntilTerminated, ResultCode);

    // Firewall rule
    if WizardIsTaskSelected('firewall') then
    begin
      Exec('netsh', 'advfirewall firewall delete rule name="Queue System Port 3000"',
        '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
      Exec('netsh', 'advfirewall firewall add rule name="Queue System Port 3000" dir=in action=allow protocol=TCP localport=3000',
        '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    end;

    // เริ่ม service
    Exec(NssmExe, 'start QueueSystem', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  end;
end;

// ── ถอนการติดตั้ง ────────────────────────────────────────────────────────
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  NssmExe: string;
  ResultCode: Integer;
begin
  if CurUninstallStep = usUninstall then
  begin
    NssmExe := ExpandConstant('{app}\tools\nssm.exe');
    Exec(NssmExe, 'stop QueueSystem', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Sleep(1000);
    Exec(NssmExe, 'remove QueueSystem confirm', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Exec('netsh', 'advfirewall firewall delete rule name="Queue System Port 3000"',
      '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  end;
end;

[Run]
Filename: "http://localhost:3000"; Description: "เปิดระบบคิวในเบราว์เซอร์"; Flags: shellexec postinstall skipifsilent nowait
