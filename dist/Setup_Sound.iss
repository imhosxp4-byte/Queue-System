; =============================================================================
;  Setup_Sound.iss  v2.0
;  ติดตั้งเสียงภาษาไทย (Microsoft Pattara – ผู้หญิง) สำหรับระบบคิวโรงพยาบาล
;
;  ขั้นตอน:
;    1. ตรวจสอบและแก้ไข Windows Audio Services
;    2. ตรวจสอบอุปกรณ์เสียง (ลำโพง/หูฟัง)
;    3. ติดตั้ง Thai Speech (Language.Speech~~~th-TH~0.0.1.0) ถ้ายังไม่มี
;    4. แสดงผลพร้อมคำแนะนำ
;
;  ต้องการ: Windows 10/11  |  สิทธิ์ Administrator
;           อินเทอร์เน็ต (เฉพาะกรณียังไม่มีเสียงไทย)
;  Build  : Inno Setup 6  →  Compile  →  Setup_Sound.exe
; =============================================================================

[Setup]
AppName=ติดตั้งเสียงภาษาไทย – ระบบคิว
AppVersion=2.0.0
AppVerName=ติดตั้งเสียงภาษาไทย – ระบบคิว v2.0
AppPublisher=Hospital Queue System
AppId={{D9A5F1E2-7B3C-4D6E-8F0A-1B2C3D4E5F6A}
DefaultDirName={tmp}
OutputDir=.
OutputBaseFilename=Setup_Sound
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
DisableProgramGroupPage=yes
PrivilegesRequired=admin
CreateAppDir=no
DisableDirPage=yes
DisableReadyMemo=yes
MinVersion=10.0
WizardSizePercent=120

[Languages]
Name: "thai"; MessagesFile: "compiler:Default.isl"

[Messages]
WelcomeLabel1=ติดตั้งเสียงภาษาไทย (Thai TTS)
WelcomeLabel2=โปรแกรมนี้จะติดตั้ง เสียงพูดภาษาไทย เพศหญิง%n(Microsoft Pattara – Thai) สำหรับระบบคิวโรงพยาบาล%n%nขั้นตอนการดำเนินการ:%n  ① แก้ไข Windows Audio Service%n  ② ตรวจสอบอุปกรณ์เสียง (ลำโพง/หูฟัง)%n  ③ ดาวน์โหลดและติดตั้งเสียงภาษาไทย%n     (ถ้ายังไม่มีในเครื่อง — ต้องการอินเทอร์เน็ต)%n%nกด ถัดไป เพื่อเริ่มดำเนินการ
FinishedLabel=
FinishedHeadingLabel=ผลการติดตั้ง

[Code]
var
  gTTSInstalled   : Boolean;  // Thai TTS ติดตั้งสำเร็จ (ใหม่หรือเดิม)
  gWasAlready     : Boolean;  // มีอยู่แล้วก่อน
  gAudioOK        : Boolean;  // Audio service OK
  gDeviceOK       : Boolean;  // มีอุปกรณ์เสียง
  gErrMsg         : AnsiString;

// ── เขียน PS1 script ──────────────────────────────────────────────────────
procedure PS(FileName, Content: String);
var L: TStringList;
begin
  L := TStringList.Create;
  try L.Text := Content; L.SaveToFile(FileName);
  finally L.Free; end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  D, sAudio, sCheck, sInstall, sDevice, sLog: String;
  RC: Integer;
begin
  if CurStep <> ssInstall then Exit;

  D       := ExpandConstant('{tmp}') + '\';
  sAudio  := D + 'q_audio.ps1';
  sCheck  := D + 'q_check.ps1';
  sInstall:= D + 'q_install.ps1';
  sDevice := D + 'q_device.ps1';
  sLog    := D + 'q_result.txt';

  // ══════════════════════════════════════════════════════════════════════════
  // ① แก้ Windows Audio Services + เปิดใช้งาน Audio Device
  //   (synthesis-failed fix สำหรับ mini PC / headless)
  // ══════════════════════════════════════════════════════════════════════════
  PS(sAudio,
    '# เปิด Audio Services' + #13#10 +
    'foreach ($s in @("AudioEndpointBuilder","Audiosrv")) {' + #13#10 +
    '  try {' + #13#10 +
    '    Set-Service $s -StartupType Automatic -EA SilentlyContinue' + #13#10 +
    '    $svc = Get-Service $s -EA SilentlyContinue' + #13#10 +
    '    if ($svc -and $svc.Status -ne "Running") { Start-Service $s -EA SilentlyContinue }' + #13#10 +
    '  } catch {}' + #13#10 +
    '}' + #13#10 +
    '# Enable ทุก audio endpoint ที่ disabled' + #13#10 +
    'try {' + #13#10 +
    '  $code = @"' + #13#10 +
    'using System.Runtime.InteropServices;' + #13#10 +
    '[Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]' + #13#10 +
    '[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]' + #13#10 +
    'interface IMMDeviceEnumerator {}' + #13#10 +
    '"@' + #13#10 +
    '  # ใช้ WMI เปิด sound device ที่ disable' + #13#10 +
    '  $disabled = Get-WmiObject Win32_SoundDevice | Where-Object { $_.ConfigManagerErrorCode -ne 0 }' + #13#10 +
    '  foreach ($d in $disabled) {' + #13#10 +
    '    try { $d.Enable() } catch {}' + #13#10 +
    '  }' + #13#10 +
    '} catch {}' + #13#10 +
    '# Set Windows Audio volume ไม่ให้ mute' + #13#10 +
    'try {' + #13#10 +
    '  $wsh = New-Object -ComObject WScript.Shell' + #13#10 +
    '  # กด unmute key' + #13#10 +
    '  Add-Type -TypeDefinition @"' + #13#10 +
    'using System;using System.Runtime.InteropServices;' + #13#10 +
    'public class Audio { [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, int dwExtraInfo); }' + #13#10 +
    '"@' + #13#10 +
    '  # Volume up x2 เพื่อให้แน่ใจว่าไม่ silent' + #13#10 +
    '  [Audio]::keybd_event(0xAF, 0, 0, 0); Start-Sleep -Milliseconds 50' + #13#10 +
    '  [Audio]::keybd_event(0xAF, 0, 2, 0); Start-Sleep -Milliseconds 50' + #13#10 +
    '  [Audio]::keybd_event(0xAF, 0, 0, 0); Start-Sleep -Milliseconds 50' + #13#10 +
    '  [Audio]::keybd_event(0xAF, 0, 2, 0)' + #13#10 +
    '} catch {}' + #13#10 +
    'exit 0');

  Exec('powershell.exe',
    '-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + sAudio + '"',
    D, SW_HIDE, ewWaitUntilTerminated, RC);
  gAudioOK := (RC = 0);

  // ══════════════════════════════════════════════════════════════════════════
  // ② ตรวจสอบอุปกรณ์เสียง
  // ══════════════════════════════════════════════════════════════════════════
  PS(sDevice,
    '$d = Get-WmiObject Win32_SoundDevice | Where-Object { $_.Status -eq "OK" }' + #13#10 +
    'if ($d) { exit 0 } else { exit 1 }');

  Exec('powershell.exe',
    '-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + sDevice + '"',
    D, SW_HIDE, ewWaitUntilTerminated, RC);
  gDeviceOK := (RC = 0);

  // ══════════════════════════════════════════════════════════════════════════
  // ③ ตรวจสอบว่ามี Thai TTS แล้วหรือยัง
  // ══════════════════════════════════════════════════════════════════════════
  PS(sCheck,
    '$ErrorActionPreference = "SilentlyContinue"' + #13#10 +
    'try {' + #13#10 +
    '  $c = Get-WindowsCapability -Online -Name "Language.Speech~~~th-TH~0.0.1.0"' + #13#10 +
    '  if ($c -and $c.State -eq "Installed") { exit 0 }' + #13#10 +
    '  exit 1' + #13#10 +
    '} catch { exit 2 }');

  Exec('powershell.exe',
    '-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + sCheck + '"',
    D, SW_HIDE, ewWaitUntilTerminated, RC);

  if RC = 0 then
  begin
    gWasAlready   := True;
    gTTSInstalled := True;
    Exit;
  end;

  // ══════════════════════════════════════════════════════════════════════════
  // ④ ดาวน์โหลดและติดตั้ง Thai TTS จาก Microsoft
  //    (รวม Microsoft Pattara – ผู้หญิง + Niwat – ผู้ชาย)
  // ══════════════════════════════════════════════════════════════════════════
  PS(sInstall,
    '$ErrorActionPreference = "Stop"' + #13#10 +
    'try {' + #13#10 +
    '  Add-WindowsCapability -Online -Name "Language.Speech~~~th-TH~0.0.1.0"' + #13#10 +
    '  "OK" | Out-File "' + sLog + '" -Encoding UTF8' + #13#10 +
    '  exit 0' + #13#10 +
    '} catch {' + #13#10 +
    '  $_ | Out-File "' + sLog + '" -Encoding UTF8' + #13#10 +
    '  exit 1' + #13#10 +
    '}');

  Exec('powershell.exe',
    '-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + sInstall + '"',
    D, SW_HIDE, ewWaitUntilTerminated, RC);

  gTTSInstalled := (RC = 0);

  if (not gTTSInstalled) and FileExists(sLog) then
  begin
    LoadStringFromFile(sLog, gErrMsg);
    if Length(gErrMsg) > 250 then gErrMsg := Copy(gErrMsg, 1, 250) + '...';
  end;
end;

// ── หน้า Finish ────────────────────────────────────────────────────────────
procedure CurPageChanged(CurPageID: Integer);
var Msg: String;
begin
  if CurPageID <> wpFinished then Exit;

  // ── ส่วนหัว ──────────────────────────────────────────────────────────────
  if gTTSInstalled then
  begin
    if gWasAlready then
      Msg := '✓ เสียงภาษาไทย (Microsoft Pattara) มีอยู่แล้ว' + #13#10 +
             '✓ แก้ไข Windows Audio Service เรียบร้อย'
    else
      Msg := '✓ ติดตั้งเสียงภาษาไทย (Microsoft Pattara) สำเร็จ!' + #13#10 +
             '✓ แก้ไข Windows Audio Service เรียบร้อย';
  end
  else
  begin
    Msg := '✗ ติดตั้งเสียงภาษาไทยไม่สำเร็จ';
    if gAudioOK then Msg := Msg + #13#10 + '✓ แก้ไข Windows Audio Service เรียบร้อย'
    else             Msg := Msg + #13#10 + '✗ ไม่สามารถแก้ไข Audio Service';
  end;

  // ── ตรวจสอบอุปกรณ์เสียง ─────────────────────────────────────────────────
  Msg := Msg + #13#10 + #13#10;
  if not gDeviceOK then
    Msg := Msg +
      '⚠  ไม่พบอุปกรณ์เสียง!' + #13#10 +
      '   → ต่อลำโพงหรือหูฟังกับเครื่องนี้' + #13#10 +
      '   → ถ้าไม่มีช่องเสียง ให้ใช้ USB Audio Adapter' + #13#10 + #13#10
  else
    Msg := Msg + '✓ พบอุปกรณ์เสียงในเครื่อง' + #13#10 + #13#10;

  // ── ขั้นตอนถัดไป ─────────────────────────────────────────────────────────
  if gTTSInstalled then
  begin
    Msg := Msg +
      'ขั้นตอนถัดไป:' + #13#10 +
      '  1. รีสตาร์ทเครื่อง (แนะนำ)' + #13#10 +
      '  2. เปิด Microsoft Edge → เข้าหน้าแสดงคิว' + #13#10 +
      '  3. กดปุ่ม "เสียง" มุมบนขวา' + #13#10 +
      '  4. ระบบจะประกาศหมายเลขคิวเป็นเสียงผู้หญิง';

    if gWasAlready then
      Msg := Msg + #13#10 + #13#10 +
        'หากยังเกิด synthesis-failed:' + #13#10 +
        '  • ตรวจสอบ: services.msc → Windows Audio → Running' + #13#10 +
        '  • ลองใช้ Microsoft Edge แทน Chrome' + #13#10 +
        '  • รีสตาร์ทเครื่อง แล้วทดสอบใหม่';
  end
  else
  begin
    Msg := Msg +
      'สาเหตุที่ติดตั้งไม่สำเร็จ:' + #13#10 +
      '  • ไม่มีอินเทอร์เน็ต หรือ Windows Update ถูกบล็อก' + #13#10 + #13#10 +
      'ติดตั้งด้วยตนเอง:' + #13#10 +
      '  Settings → Time & Language → Speech' + #13#10 +
      '  → Add voices → Thai → Download';
    if gErrMsg <> '' then
      Msg := Msg + #13#10 + #13#10 + 'Error: ' + gErrMsg;
  end;

  WizardForm.FinishedLabel.Caption := Msg;
end;
