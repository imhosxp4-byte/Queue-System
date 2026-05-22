/**
 * Queue System — Local Print Agent
 * รันบนเครื่อง Client เพื่อปริ้นโดยตรงโดยไม่ผ่าน browser dialog
 * Port: 3001  (แยกจาก Queue Server port 3000)
 */
const http = require('http');
const { exec } = require('child_process');
const os   = require('os');
const fs   = require('fs');
const path = require('path');

const PORT    = 3001;
// When packaged as .exe (pkg), __dirname points inside the snapshot FS.
// Use process.execPath dir so config file sits next to the .exe on disk.
const APP_DIR     = typeof process.pkg !== 'undefined' ? path.dirname(process.execPath) : __dirname;
const CONFIG_FILE = path.join(APP_DIR, 'local-print-config.json');

// ── Local print config ────────────────────────────────────────────────────
const DEFAULT_CONFIG = {
  paperSize: '80mm', customWidth: 80, customHeight: 200,
  showHeader: true, headerName: '', headerSubtitle: '', headerFontSize: 14,
  showDividerLine: true,
  showPatientName: true, showHnQn: true, patientFontSize: 11,
  showQueueType: true, queueTypeFontSize: 11,
  queueNumFontSize: 60,
  showDateTime: true, dateFontSize: 9,
  showFooter: false, footerText: '', footerFontSize: 8,
  autoPrint: true, copies: 1,
  fontFamily: '',
  layoutOrder: ['header','patientName','hnQn','queueType','queueNum','dateTime','footer'],
};

function loadConfig() {
  try {
    return Object.assign({}, DEFAULT_CONFIG, JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8')));
  } catch {
    return Object.assign({}, DEFAULT_CONFIG);
  }
}

function saveConfig(cfg) {
  fs.writeFileSync(CONFIG_FILE, JSON.stringify(cfg, null, 2), 'utf8');
}

let localCfg = loadConfig();

// ── Helpers ───────────────────────────────────────────────────────────────
function cors(res) {
  res.setHeader('Access-Control-Allow-Origin',  '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
}

function readBody(req) {
  return new Promise(resolve => {
    let data = '';
    req.on('data', c => data += c);
    req.on('end', () => { try { resolve(JSON.parse(data)); } catch { resolve({}); } });
  });
}

function sendJson(res, obj, status = 200) {
  const body = JSON.stringify(obj);
  res.writeHead(status, { 'Content-Type': 'application/json' });
  res.end(body);
}

function getPrinters(cb) {
  exec('powershell -NoProfile -Command "Get-Printer | Select-Object -ExpandProperty Name"',
    { timeout: 6000, windowsHide: true }, (err, stdout) => {
      if (err) { cb([]); return; }
      cb(stdout.split('\n').map(p => p.trim()).filter(Boolean));
    });
}

// ── Calculate paper height from content (for printers without auto-cut) ──────
function calcPrintHeight(lines, bottomMargin = 8) {
  let y = 3; // top margin
  for (const line of lines) {
    if (line.t === 'div') {
      y += 3.0;
    } else if (line.t === 'numWithType') {
      const lh = (line.numFs / 72.0 * 25.4) * 1.5;
      y += lh + 1.5;
    } else {
      const lh = (line.fs / 72.0 * 25.4) * 1.5;
      y += lh + 1.5;
    }
  }
  return Math.ceil(y + bottomMargin);
}

// ── Build print lines (same layout logic as server) ───────────────────────
function buildLines(cfg, ticket) {
  const lines = [];
  const c = (x, d) => x !== undefined && x !== null ? x : d;
  const DEFAULT_ORDER = ['header','patientName','hnQn','queueType','queueNum','dateTime','footer'];
  const order = (cfg.layoutOrder && cfg.layoutOrder.length) ? cfg.layoutOrder : DEFAULT_ORDER;

  const builders = {
    header: () => {
      if (!c(cfg.showHeader, true)) return;
      lines.push({ t:'text', text: c(cfg.headerName, ticket.sysName || 'ระบบคิว'), fs: c(cfg.headerFontSize,14), bold:true, color:'Black' });
      if (cfg.headerSubtitle) lines.push({ t:'text', text: cfg.headerSubtitle, fs: Math.max(7,(c(cfg.headerFontSize,14)-3)), bold:false, color:'DimGray' });
    },
    patientName: () => {
      if (!c(cfg.showPatientName, true) || !ticket.patientName) return;
      lines.push({ t:'text', text: ticket.patientName, fs: c(cfg.patientFontSize,11), bold:true, color:'Black' });
    },
    hnQn: () => {
      if (!c(cfg.showHnQn, true)) return;
      const parts = [ticket.hn?'HN: '+ticket.hn:'', ticket.qn?'QN: '+ticket.qn:''].filter(Boolean);
      if (parts.length) lines.push({ t:'text', text: parts.join('   '), fs: Math.max(7,c(cfg.patientFontSize,11)-2), bold:false, color:'DimGray' });
    },
    queueType: () => {
      if (c(cfg.queueTypePosition, 'above') === 'left') return; // rendered with queueNum
      if (!c(cfg.showQueueType, true) || !ticket.typeName) return;
      lines.push({ t:'text', text: ticket.typeName, fs: c(cfg.queueTypeFontSize,11), bold:false, color:'Black' });
    },
    queueNum: () => {
      if (c(cfg.queueTypePosition, 'above') === 'left' && c(cfg.showQueueType, true) && ticket.typeName) {
        lines.push({ t:'numWithType', typeText: ticket.typeName, typeFs: c(cfg.queueTypeFontSize,11),
                     numText: ticket.display, numFs: c(cfg.queueNumFontSize,60) });
      } else {
        lines.push({ t:'num', text: ticket.display, fs: c(cfg.queueNumFontSize,60), bold:true, color:'Black' });
      }
    },
    dateTime: () => {
      if (!c(cfg.showDateTime, true)) return;
      lines.push({ t:'text', text: `${ticket.date}  ${ticket.issuedAt}`, fs: c(cfg.dateFontSize,9), bold:false, color:'DimGray' });
    },
    footer: () => {
      if (!c(cfg.showFooter, true) || !cfg.footerText) return;
      cfg.footerText.split('\n').forEach(l => {
        if (l.trim()) lines.push({ t:'text', text: l, fs: c(cfg.footerFontSize,8), bold:false, color:'DimGray' });
      });
    }
  };

  for (const id of order) {
    if (id === 'divider') {
      if (c(cfg.showDividerLine, true) && lines.length && lines[lines.length-1]?.t !== 'div')
        lines.push({ t:'div' });
    } else if (builders[id]) {
      builders[id]();
    }
  }
  return lines;
}

// ── Print via PowerShell GDI+ ─────────────────────────────────────────────
function runPrint(printerName, paperMm, paperHmm, copies, fontFamily, lines, cb) {
  const ts       = Date.now();
  const dataFile = path.join(os.tmpdir(), `qpa_data_${ts}.json`);
  const ps1File  = path.join(os.tmpdir(), `qpa_print_${ts}.ps1`);
  const safeFont = (fontFamily || 'Segoe UI').replace(/['"]/g, '');
  fs.writeFileSync(dataFile, JSON.stringify({ printerName, paperMm, paperHmm: paperHmm || 300, copies: Math.max(1, copies || 1), fontFamily: safeFont, lines }), 'utf8');
  const esc = dataFile.replace(/\\/g,'\\\\').replace(/'/g,"''");
  const ps = `
Add-Type -AssemblyName System.Drawing
$script:d = Get-Content '${esc}' -Raw -Encoding utf8 | ConvertFrom-Json
$pw100 = [int]($script:d.paperMm / 25.4 * 100)
$ph100 = if($script:d.paperHmm -gt 0){[int]($script:d.paperHmm / 25.4 * 100)}else{2000}
$script:fontName = if($script:d.fontFamily -and $script:d.fontFamily -ne ''){$script:d.fontFamily}else{'Segoe UI'}

function DoPrint {
  $pd = New-Object System.Drawing.Printing.PrintDocument
  $pd.PrinterSettings.PrinterName = $script:d.printerName
  $pd.PrinterSettings.Copies = [int16]1
  $pd.DefaultPageSettings.PaperSize = New-Object System.Drawing.Printing.PaperSize('Custom',$pw100,$ph100)
  $pd.DefaultPageSettings.Margins = New-Object System.Drawing.Printing.Margins(0,0,0,0)
  $pd.add_PrintPage({
    param($s,$e)
    $g=$e.Graphics; $g.PageUnit=[System.Drawing.GraphicsUnit]::Millimeter
    [float]$pw=$script:d.paperMm-6.0; [float]$m=3.0; [float]$y=$m
    foreach($line in $script:d.lines){
      if($line.t -eq 'div'){
        $pen=New-Object System.Drawing.Pen([System.Drawing.Color]::LightGray,[float]0.3)
        $pen.DashStyle=[System.Drawing.Drawing2D.DashStyle]::Dash
        $g.DrawLine($pen,$m,$y,($m+$pw),$y); $y+=[float]3.0
      }elseif($line.t -eq 'numWithType'){
        [float]$typeSmm=$line.typeFs/72.0*25.4
        [float]$numSmm=$line.numFs/72.0*25.4
        [float]$lh=$numSmm*1.5
        [float]$leftW=$pw*[float]0.35
        [float]$gap=[float]2.0
        [float]$rightW=$pw-$leftW-$gap
        [float]$rightX=$m+$leftW+$gap
        $typeFont=New-Object System.Drawing.Font($script:fontName,$typeSmm,[System.Drawing.FontStyle]::Regular,[System.Drawing.GraphicsUnit]::Millimeter)
        $numFont=New-Object System.Drawing.Font($script:fontName,$numSmm,[System.Drawing.FontStyle]::Bold,[System.Drawing.GraphicsUnit]::Millimeter)
        $fmt=New-Object System.Drawing.StringFormat
        $fmt.Alignment=[System.Drawing.StringAlignment]::Center
        $fmt.LineAlignment=[System.Drawing.StringAlignment]::Center
        $leftRect=New-Object System.Drawing.RectangleF($m,$y,$leftW,$lh)
        $g.DrawString($line.typeText,$typeFont,[System.Drawing.Brushes]::Black,$leftRect,$fmt)
        $bpen=New-Object System.Drawing.Pen([System.Drawing.Color]::Black,[float]0.7)
        $g.DrawRectangle($bpen,$rightX,$y,$rightW,$lh)
        $rightRect=New-Object System.Drawing.RectangleF($rightX,$y,$rightW,$lh)
        $g.DrawString($line.numText,$numFont,[System.Drawing.Brushes]::Black,$rightRect,$fmt)
        $y+=$lh+[float]1.5
      }else{
        [float]$smm=$line.fs/72.0*25.4
        $st=if($line.bold){[System.Drawing.FontStyle]::Bold}else{[System.Drawing.FontStyle]::Regular}
        $font=New-Object System.Drawing.Font($script:fontName,$smm,$st,[System.Drawing.GraphicsUnit]::Millimeter)
        $brush=[System.Drawing.Brushes]::($line.color)
        if(-not $brush){$brush=[System.Drawing.Brushes]::Black}
        $fmt=New-Object System.Drawing.StringFormat
        $fmt.Alignment=[System.Drawing.StringAlignment]::Center
        $fmt.LineAlignment=[System.Drawing.StringAlignment]::Center
        [float]$lh=$smm*1.5
        if($line.t -eq 'num'){
          $bpen=New-Object System.Drawing.Pen([System.Drawing.Color]::Black,[float]0.7)
          $g.DrawRectangle($bpen,$m,$y,$pw,$lh)
        }
        $rect=New-Object System.Drawing.RectangleF($m,$y,$pw,$lh)
        $g.DrawString($line.text,$font,$brush,$rect,$fmt)
        $y+=$lh+[float]1.5
      }
    }
  })
  $pd.Print()
}

for($i=0; $i -lt [int]$script:d.copies; $i++){
  DoPrint
  if($i -lt ([int]$script:d.copies - 1)){ Start-Sleep -Milliseconds 300 }
}
`;
  fs.writeFileSync(ps1File, ps, 'utf8');
  exec(`powershell -NoProfile -ExecutionPolicy Bypass -File "${ps1File}"`,
    { timeout: 30000, windowsHide: true }, (err, stdout, stderr) => {
      try { fs.unlinkSync(ps1File); } catch {}
      try { fs.unlinkSync(dataFile); } catch {}
      cb(err, stderr);
    });
}

// ── HTTP Server ───────────────────────────────────────────────────────────
const server = http.createServer((req, res) => {
  cors(res);
  if (req.method === 'OPTIONS') { res.writeHead(204); res.end(); return; }

  // GET /api/printers
  if (req.method === 'GET' && req.url === '/api/printers') {
    getPrinters(printers => sendJson(res, { printers }));
    return;
  }

  // GET /api/print-config — return local config
  if (req.method === 'GET' && req.url === '/api/print-config') {
    sendJson(res, localCfg);
    return;
  }

  // POST /api/print-config — save local config
  if (req.method === 'POST' && req.url === '/api/print-config') {
    readBody(req).then(body => {
      Object.assign(localCfg, body);
      saveConfig(localCfg);
      sendJson(res, { success: true, printConfig: localCfg });
    });
    return;
  }

  // POST /api/local-print
  if (req.method === 'POST' && req.url === '/api/local-print') {
    readBody(req).then(body => {
      const { printerName, ticket, cfg } = body;
      if (!printerName) { sendJson(res, { success: false, message: 'ไม่ได้ระบุเครื่องพิมพ์' }); return; }
      const useCfg = Object.assign({}, localCfg, cfg || {});
      const paperMm  = (useCfg.paperSize === '58mm') ? 58
                     : (useCfg.paperSize === 'a4')    ? 210
                     : (useCfg.paperSize === 'custom') ? (Number(useCfg.customWidth) || 80)
                     : 80;
      const lines    = buildLines(useCfg, ticket || {});
      const paperHmm = (useCfg.paperSize === 'a4') ? 297
                     : (useCfg.paperSize === 'custom' && Number(useCfg.customHeight)) ? Number(useCfg.customHeight)
                     : calcPrintHeight(lines);
      const copies  = Math.max(1, Number(useCfg.copies) || 1);
      const font    = useCfg.fontFamily || '';
      runPrint(printerName, paperMm, paperHmm, copies, font, lines, (err, stderr) => {
        if (err) sendJson(res, { success: false, message: (stderr || err.message).trim() });
        else     sendJson(res, { success: true });
      });
    });
    return;
  }

  // GET /ping
  if (req.method === 'GET' && req.url === '/ping') {
    sendJson(res, { ok: true, hostname: os.hostname() });
    return;
  }

  res.writeHead(404); res.end('Not found');
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`Queue Print Agent  http://localhost:${PORT}`);
  console.log(`Config: ${CONFIG_FILE}`);
  console.log('พร้อมรับคำสั่งปริ้นจากเครื่องอื่น — กด Ctrl+C เพื่อหยุด');
});
