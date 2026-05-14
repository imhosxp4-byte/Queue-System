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

[CustomMessages]
thai.WelcomeLabel1=ยินดีต้อนรับสู่ตัวติดตั้ง%nระบบคิว (Queue System)
thai.WelcomeLabel2=ตัวช่วยนี้จะติดตั้งระบบคิวลงในเครื่องของคุณ%n%nระบบจะรันเป็น Windows Service โดยอัตโนมัติ%nไม่ต้องเปิด Command Prompt%n%nกดถัดไปเพื่อดำเนินการต่อ
thai.FinishedHeadingLabel=ติดตั้งระบบคิวเสร็จสมบูรณ์
thai.FinishedLabelNoIcons=ระบบคิวถูกติดตั้งและเริ่มทำงานเป็น Windows Service แล้ว%n%nเปิดใช้งานได้ที่: http://localhost:3000

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
function ServiceExists(ServiceName: string): Boolean;
var
  ResultCode: Integer;
begin
  Exec(ExpandConstant('{app}\tools\nssm.exe'), 'status ' + ServiceName,
    '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Result := (ResultCode <> 3);
end;

procedure CreateUrlShortcut();
var
  ShortcutFile: string;
  Lines: TStringList;
begin
  ShortcutFile := ExpandConstant('{app}\open-queue.url');
  Lines := TStringList.Create;
  try
    Lines.Add('[InternetShortcut]');
    Lines.Add('URL=http://localhost:3000');
    Lines.Add('IconFile=' + ExpandConstant('{app}\QueueServer.exe'));
    Lines.Add('IconIndex=0');
    Lines.SaveToFile(ShortcutFile);
  finally
    Lines.Free;
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  AppDir, NssmExe: string;
  ResultCode: Integer;
begin
  if CurStep = ssPostInstall then
  begin
    AppDir  := ExpandConstant('{app}');
    NssmExe := AppDir + '\tools\nssm.exe';

    // Create browser shortcut file
    CreateUrlShortcut();

    // Stop & remove old service if exists
    if ServiceExists('QueueSystem') then
    begin
      Exec(NssmExe, 'stop QueueSystem', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
      Exec(NssmExe, 'remove QueueSystem confirm', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
      Sleep(1500);
    end;

    // Install service
    Exec(NssmExe, 'install QueueSystem "' + AppDir + '\QueueServer.exe"',
      '', SW_HIDE, ewWaitUntilTerminated, ResultCode);

    // Configure service
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

    // Start service
    Exec(NssmExe, 'start QueueSystem', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  end;
end;

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
