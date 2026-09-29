# ClaudeUsageWidget - 바탕화면용 Claude Code 사용량 카드 위젯
# Windows PowerShell 5.1 + WinForms 만 사용 (추가 설치 없음)

$ErrorActionPreference = 'Stop'
$AppDir       = Split-Path -Parent $MyInvocation.MyCommand.Path
$DataDir      = Join-Path $env:LOCALAPPDATA 'ClaudeUsageWidget'
$UsageFile    = Join-Path $DataDir 'usage.txt'
$SettingsFile = Join-Path $DataDir 'settings.json'
$FetchScript  = Join-Path $AppDir 'fetch-usage.ps1'
New-Item -ItemType Directory -Force -Path $DataDir | Out-Null

# ---- 단일 인스턴스 ---------------------------------------------------------------
$created = $false
$mutex = New-Object Threading.Mutex($true, 'Local\ClaudeUsageWidget', [ref]$created)
if (-not $created) { exit }

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -Namespace CUW -Name Native -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
[DllImport("user32.dll")] public static extern bool ReleaseCapture();
[DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, int msg, IntPtr w, IntPtr l);
[DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int idx);
[DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr h, int idx, int v);
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
[DllImport("user32.dll")] public static extern bool DestroyIcon(IntPtr h);
[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string c, string t);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindowEx(IntPtr p, IntPtr a, string c, string t);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, [In, Out] int[] r);
[DllImport("shell32.dll")] public static extern int SHQueryUserNotificationState(out int s);
[DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr h, int attr, ref int val, int size);
'@

try { $cw = [CUW.Native]::GetConsoleWindow(); if ($cw -ne [IntPtr]::Zero) { [void][CUW.Native]::ShowWindow($cw, 0) } } catch {}
try { [void][CUW.Native]::SetProcessDPIAware() } catch {}
[Windows.Forms.Application]::EnableVisualStyles()
[Windows.Forms.Application]::SetUnhandledExceptionMode([Windows.Forms.UnhandledExceptionMode]::CatchException)
[Windows.Forms.Application]::add_ThreadException({ param($s, $e) })

# ---- 설정 ------------------------------------------------------------------------
$Cfg = @{ X = -1; Y = -1; Interval = 180; IntervalV2 = $false; Opacity = 1.0; ZMode = 'desktop'; AutoRefresh = $true; ShowAbs = $false; Theme = 'dark'; TaskbarStrip = $true
         Alerts = $true; WarnPct = 85; AlertPct = 95; PaceWarn = $true; CreditAlert = $true; Notified = ''; CreditSeen = -1.0 }
if (Test-Path $SettingsFile) {
  try { $j = [IO.File]::ReadAllText($SettingsFile) | ConvertFrom-Json; foreach ($p in $j.PSObject.Properties) { if ($Cfg.ContainsKey($p.Name)) { $Cfg[$p.Name] = $p.Value } } } catch {}
}
if ([double]$Cfg.Opacity -lt 0.3) { $Cfg.Opacity = 1.0 }
# 1분 주기는 429 가 잦아서 기본을 3분으로 (예전 설정 1회 이전)
if (-not $Cfg.IntervalV2) { if ([int]$Cfg.Interval -lt 180) { $Cfg.Interval = 180 }; $Cfg.IntervalV2 = $true }
if ([int]$Cfg.Interval -lt 120) { $Cfg.Interval = 120 }
function Save-Settings { try { [IO.File]::WriteAllText($SettingsFile, ($Cfg | ConvertTo-Json)) } catch {} }

$RunKey  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$RunName = 'ClaudeUsageWidget'
function Get-LaunchCommand {
  $exe = Join-Path $AppDir 'ClaudeUsageWidget.exe'          # 콘솔 없이 띄우는 런처 (Windows Terminal 창 방지)
  if (Test-Path $exe) { return "`"$exe`"" }
  $ps = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $argStr = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$(Join-Path $AppDir 'widget.ps1')`""
  $conhost = Join-Path $env:WINDIR 'System32\conhost.exe'
  if ([Environment]::OSVersion.Version.Build -ge 17763 -and (Test-Path $conhost)) { return "`"$conhost`" --headless `"$ps`" $argStr" }
  return "`"$ps`" $argStr"
}
function Test-AutoStart { try { $null -ne (Get-ItemProperty -Path $RunKey -Name $RunName -ErrorAction Stop) } catch { $false } }
function Set-AutoStart([bool]$on) {
  if ($on) { Set-ItemProperty -Path $RunKey -Name $RunName -Value (Get-LaunchCommand) }
  else { Remove-ItemProperty -Path $RunKey -Name $RunName -ErrorAction SilentlyContinue }
}

# ---- 테마 / 폰트 ------------------------------------------------------------------
function C($r, $g, $b, $a = 255) { [Drawing.Color]::FromArgb($a, $r, $g, $b) }
$Themes = @{
  light = @{
    Bg = (C 250 250 253); GradTop = (C 255 255 255); GradBot = (C 244 245 250); Border = (C 222 224 230); Txt = (C 22 24 30); Sec = (C 92 97 110); Dim2 = (C 140 144 156); Track = (C 233 235 240)
    Hover = (C 0 0 0 14); Div = (C 230 232 238); Blue = (C 40 104 232); Amber = (C 214 132 10); Red = (C 214 48 62)
    Ok = (C 28 160 84); Week = (C 108 92 214); Five = (C 222 100 56); Model = (C 40 160 104)
  }
  dark = @{
    Bg = (C 26 27 38); GradTop = (C 34 35 54); GradBot = (C 21 22 29); Border = (C 70 74 100); Txt = (C 238 238 243); Sec = (C 160 162 178); Dim2 = (C 120 122 138); Track = (C 58 60 70)
    Hover = (C 255 255 255 14); Div = (C 62 64 78); Blue = (C 100 152 255); Amber = (C 242 182 64); Red = (C 242 98 98)
    Ok = (C 126 170 52); Week = (C 128 116 226); Five = (C 226 114 74); Model = (C 76 178 128)
  }
}
function Set-Theme($name) {
  if (-not $Themes.ContainsKey("$name")) { $name = 'light' }
  $script:Col = $Themes["$name"]
  $script:Col.Bg2 = $script:Col.Bg; $script:Col.Dim = $script:Col.Sec    # 트레이 아이콘용 별칭
  if ($form) { $form.BackColor = $script:Col.Bg; $form.Invalidate() }
}
$form = $null
Set-Theme $Cfg.Theme

$Fnt = @{
  Title = (New-Object Drawing.Font('Malgun Gothic', 11.5, [Drawing.FontStyle]::Bold))
  Lbl   = (New-Object Drawing.Font('Malgun Gothic', 9))
  Pct   = (New-Object Drawing.Font('Segoe UI Semibold', 9.5))
  Sec   = (New-Object Drawing.Font('Malgun Gothic', 8.25))
  Big   = (New-Object Drawing.Font('Segoe UI Semibold', 24))
  Val   = (New-Object Drawing.Font('Segoe UI Semibold', 12))
}
$SfC = New-Object Drawing.StringFormat; $SfC.LineAlignment = 'Center'; $SfC.Alignment = 'Center'
$TF = [Windows.Forms.TextFormatFlags]
$TFBase = [Windows.Forms.TextFormatFlags]'VerticalCenter, SingleLine, NoPadding, NoPrefix'

function ToPct($v) { $n = 0.0; [void][double]::TryParse("$v", [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$n); [Math]::Max(0.0, [Math]::Min(100.0, $n)) }
function PctColor([double]$p) { if ($p -ge 90) { $Col.Red } elseif ($p -ge 70) { $Col.Amber } else { $Col.Blue } }
function V($key) { $v = $script:D[$key]; if ($null -eq $v -or $v -eq '') { '-' } else { $v } }
function NowTs { [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }
function LeftFromTs($ts) {
  $n = 0L; if (-not [int64]::TryParse("$ts", [ref]$n) -or $n -le 0) { return '-' }
  $s = $n - (NowTs); if ($s -le 0) { return '곧 리셋' }
  $d = [Math]::Floor($s / 86400); $h = [Math]::Floor(($s % 86400) / 3600); $m = [Math]::Floor(($s % 3600) / 60)
  if ($d -ge 1) { return ('{0}일 {1}시간 남음' -f $d, $h) }
  if ($h -ge 1) { return ('{0}시간 {1}분 남음' -f $h, $m) }
  if ($m -ge 1) { return ('{0}분 남음' -f $m) }
  return ('{0}초 남음' -f $s)
}
function AtFromTs($ts) {
  $n = 0L; if (-not [int64]::TryParse("$ts", [ref]$n) -or $n -le 0) { return '-' }
  [DateTimeOffset]::FromUnixTimeSeconds($n).ToLocalTime().ToString('M/d (ddd) HH:mm 리셋', [Globalization.CultureInfo]'ko-KR')
}
function Human([double]$n) {
  if ($n -ge 1e9) { return ('{0:0.00}B' -f ($n / 1e9)) }
  if ($n -ge 1e6) { return ('{0:0.0}M'  -f ($n / 1e6)) }
  if ($n -ge 1e3) { return ('{0:0.0}K'  -f ($n / 1e3)) }
  return ('{0:0}' -f $n)
}

# ---- 상태 -------------------------------------------------------------------------
$script:D = @{}
$script:Models = @()
$script:A = @{}
$script:hover = ''
$script:spin = 0.0
$script:regions = New-Object System.Collections.ArrayList
$script:fade = 1.0

function Get-Rows {
  $act = V 'active'
  $rows = @(
    [pscustomobject]@{ Id = 'r5'; Key = 'five'; Label = '5시간'; Pct = (ToPct (V 'five')); Ts = (V 'five_ts'); Active = ($act -eq '5h') }
    [pscustomobject]@{ Id = 'rw'; Key = 'week'; Label = '주간'; Pct = (ToPct (V 'week')); Ts = (V 'week_ts'); Active = ($act -eq 'week') }
  )
  $i = 0
  foreach ($m in $script:Models) {
    $rows += [pscustomobject]@{ Id = "m$i"; Key = "m:$($m.Name)"; Label = $m.Name; Pct = $m.Pct; Ts = $m.Ts; Active = $m.Active }
    $i++
  }
  , $rows
}
function Money($v) {
  $n = 0.0; if (-not [double]::TryParse("$v", [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$n)) { return '' }
  if ("$(V 'cr_cur')" -in 'USD', '-', '') { return ('$' + $n.ToString('0.00', [Globalization.CultureInfo]::InvariantCulture)) }
  return ('{0:0.00} {1}' -f $n, (V 'cr_cur'))
}
function Has-Credit { "$(V 'cr_on')" -eq '1' }
function Has-CreditLimit { (Money (V 'cr_limit')) -ne '' }
function Target($key) { if ($key -eq 'credit') { return (ToPct (V 'cr_pct')) }; foreach ($r in (Get-Rows)) { if ($r.Key -eq $key) { return [double]$r.Pct } }; 0.0 }
function Anim($key) { if ($script:A.ContainsKey($key)) { [double]$script:A[$key] } else { 0.0 } }

# ---- 폼 ----------------------------------------------------------------------------
$form = New-Object Windows.Forms.Form
$form.FormBorderStyle = 'None'
$form.ShowInTaskbar = $false
$form.MaximizeBox = $false
$form.StartPosition = 'Manual'
$form.BackColor = $Col.Bg
$form.Opacity = [double]$Cfg.Opacity
$form.Text = 'Claude Usage'
$form.GetType().GetProperty('DoubleBuffered', [Reflection.BindingFlags]'NonPublic,Instance').SetValue($form, $true, $null)

$g0 = $form.CreateGraphics(); $script:k = $g0.DpiX / 96.0; $g0.Dispose()
function Px([double]$v) { [float]($v * $script:k) }
function PxI([double]$v) { [int][Math]::Round($v * $script:k) }

$BaseW = 280
$Lay = @{ Header = 44; Total = 402 }
function Get-Height { $Lay.Total }
function Apply-Size {
  $sz = New-Object Drawing.Size((PxI $BaseW), (PxI (Get-Height)))
  if ($form.ClientSize -ne $sz) { $form.ClientSize = $sz; Keep-OnScreen }
}
function Keep-OnScreen {
  $scr = [Windows.Forms.Screen]::FromPoint((New-Object Drawing.Point(($form.Left + 20), ($form.Top + 20)))).WorkingArea
  $x = [Math]::Max($scr.Left, [Math]::Min($form.Left, $scr.Right - $form.Width))
  $y = [Math]::Max($scr.Top,  [Math]::Min($form.Top,  $scr.Bottom - $form.Height))
  if ($x -ne $form.Left -or $y -ne $form.Top) { $form.Location = New-Object Drawing.Point($x, $y) }
}
function Place-Initial {
  $x = [int]$Cfg.X; $y = [int]$Cfg.Y
  $ok = $false
  if ($Cfg.X -ne -1) {
    $pt = New-Object Drawing.Point(($x + 20), ($y + 20))
    foreach ($sc in [Windows.Forms.Screen]::AllScreens) { if ($sc.Bounds.Contains($pt)) { $ok = $true } }
  }
  if (-not $ok) { $wa = [Windows.Forms.Screen]::PrimaryScreen.WorkingArea; $x = $wa.Right - $form.Width - (PxI 24); $y = $wa.Bottom - $form.Height - (PxI 24) }
  $form.Location = New-Object Drawing.Point($x, $y)
}

# ---- Z-order: desktop(맨 아래) / normal / top(항상 위) ------------------------------------
function Apply-ZOrder {
  if ($script:flashUntil -gt [DateTime]::Now) { $form.TopMost = $true; return }
  switch ("$($Cfg.ZMode)") {
    'top'     { $form.TopMost = $true;  [void][CUW.Native]::SetWindowPos($form.Handle, [IntPtr](-1), 0, 0, 0, 0, 0x0013) }
    'desktop' { $form.TopMost = $false; if (-not $form.ContainsFocus -and -not $script:menu.Visible) { [void][CUW.Native]::SetWindowPos($form.Handle, [IntPtr]1, 0, 0, 0, 0, 0x0013) } }
    default   { $form.TopMost = $false }
  }
}

# ---- 그리기 도우미 -----------------------------------------------------------------------
function RoundPath([float]$x, [float]$y, [float]$w, [float]$h, [float]$r) {
  $p = New-Object Drawing.Drawing2D.GraphicsPath
  $r = [Math]::Min($r, [Math]::Min($w, $h) / 2); $d = $r * 2
  if ($d -le 0.5) { $p.AddRectangle((New-Object Drawing.RectangleF($x, $y, $w, $h))); return , $p }
  $p.AddArc($x, $y, $d, $d, 180, 90); $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
  $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90); $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
  $p.CloseFigure(); return , $p
}
function FillRound($g, $color, [float]$x, [float]$y, [float]$w, [float]$h, [float]$r) {
  if ($w -le 0.5 -or $h -le 0) { return }
  $b = New-Object Drawing.SolidBrush($color); $p = RoundPath $x $y $w $h $r
  $g.FillPath($b, $p); $p.Dispose(); $b.Dispose()
}
# GDI(ClearType) 텍스트. align: N(좌) F(우) C(가운데), x 는 기준점, cy 는 세로 중심
function T($g, $text, $font, $color, [float]$x, [float]$cy, $align = 'N', [float]$hh = 28) {
  $w = PxI 400; $h = PxI $hh; $top = [int][Math]::Round($cy - $h / 2)
  switch ($align) {
    'F' { $rect = New-Object Drawing.Rectangle(([int][Math]::Round($x) - $w), $top, $w, $h); $fl = $TFBase -bor $TF::Right }
    'C' { $rect = New-Object Drawing.Rectangle(([int][Math]::Round($x - $w / 2)), $top, $w, $h); $fl = $TFBase -bor $TF::HorizontalCenter }
    default { $rect = New-Object Drawing.Rectangle(([int][Math]::Round($x)), $top, $w, $h); $fl = $TFBase }
  }
  [Windows.Forms.TextRenderer]::DrawText($g, "$text", $font, $rect, $color, [Windows.Forms.TextFormatFlags]$fl)
}
function TW($text, $font) { [Windows.Forms.TextRenderer]::MeasureText("$text", $font, (New-Object Drawing.Size(4000, 400)), $TFBase).Width }
function Reg($id, [float]$x, [float]$y, [float]$w, [float]$h, $tipText) {
  [void]$script:regions.Add(@{ Id = $id; R = (New-Object Drawing.RectangleF($x, $y, $w, $h)); Tip = $tipText })
}

# ---- 섹션별 그리기 -------------------------------------------------------------------------
# 남은 시간을 "2일 17시간" / "3시간 58분" / "12분" 으로. 절대 시각 모드면 "9/30 04:00"
function KoLeft($ts) {
  $n = 0L; if (-not [int64]::TryParse("$ts", [ref]$n) -or $n -le 0) { return '' }
  if ($Cfg.ShowAbs) { return [DateTimeOffset]::FromUnixTimeSeconds($n).ToLocalTime().ToString('M/d HH:mm', [Globalization.CultureInfo]::InvariantCulture) }
  $s = $n - (NowTs); if ($s -le 0) { return '곧' }
  $d = [Math]::Floor($s / 86400); $h = [Math]::Floor(($s % 86400) / 3600); $m = [Math]::Floor(($s % 3600) / 60)
  if ($d -ge 1) { return ('{0}일 {1}시간' -f $d, $h) }
  if ($h -ge 1) { return ('{0}시간 {1}분' -f $h, $m) }
  return ('{0}분' -f [Math]::Max(1, $m))
}
function ResetText($ts) {
  $k = KoLeft $ts; if ($k -eq '') { return '' }
  if ($Cfg.ShowAbs) { return "$k 리셋" }
  if ($k -eq '곧') { return '곧 리셋' }
  return "$k 후 리셋"
}
function Status-Text {
  switch ("$(V 'status')") {
    '429'       { '호출 제한 · 잠시 후 재시도' }
    'error'     { '조회 실패 · 이전 값' }
    'auth'      { '인증 실패 · claude 재로그인' }
    'expired'   { '토큰 만료' }
    'nocred'    { 'claude 로그인 필요' }
    'credwrite' { '토큰 저장 실패' }
    default     { '' }
  }
}
function Plan-Text {
  $p = "$(V 'plan')"; $t = "$(V 'tier')"; $tier = ''
  if ($t -match 'max_(\d+)x') { $tier = 'Max ' + $Matches[1] + 'x' }
  $name = if ($p -in '-', '') { '' } else { (Get-Culture).TextInfo.ToTitleCase($p) }
  if ($name -eq 'Max' -and $tier) { return $tier }
  if ($name -and $tier) { return "$name · $tier" }
  if ($name) { return $name }
  return $tier
}
function AgeText {
  $n = 0L; if (-not [int64]::TryParse("$(V 'api_ts')", [ref]$n) -or $n -le 0) { return '' }
  $s = (NowTs) - $n
  if ($s -lt 60) { return '방금 갱신' }
  if ($s -lt 3600) { return ('{0}분 전 갱신' -f [Math]::Floor($s / 60)) }
  return ('{0}시간 전 갱신' -f [Math]::Floor($s / 3600))
}
function RingColor($base, [double]$p) { if ($p -ge 90) { $Col.Red } elseif ($p -ge 70) { $Col.Amber } else { $base } }
function Ring($g, [float]$cx, [float]$cy, [float]$r, [float]$sw, $color, [double]$pct) {
  $rect = New-Object Drawing.RectangleF(($cx - $r), ($cy - $r), ($r * 2), ($r * 2))
  $tp = New-Object Drawing.Pen(([Drawing.Color]::FromArgb(50, $color.R, $color.G, $color.B)), $sw); $g.DrawEllipse($tp, $rect); $tp.Dispose()
  if ($pct -gt 0.4) {
    $pen = New-Object Drawing.Pen($color, $sw); $pen.StartCap = 'Round'; $pen.EndCap = 'Round'
    $g.DrawArc($pen, $rect, -90.0, [float][Math]::Min(359.9, 3.6 * $pct)); $pen.Dispose()
  }
}

function Draw-Header($g, [float]$W, [float]$y) {
  $cy = $y + (Px 22)
  T $g 'Claude' $Fnt.Title $Col.Txt (Px 20) $cy
  $plan = Plan-Text
  if ($plan) { T $g $plan $Fnt.Lbl $Col.Sec ((Px 20) + (TW 'Claude' $Fnt.Title) + (Px 8)) $cy }
  # 우측: 상태 점 / 새로고침 / 더보기(...)
  $st = V 'status'
  $dc = switch -Regex ($st) { '^ok$' { $Col.Ok } '^(429|error)$' { $Col.Amber } '^(auth|expired|nocred|credwrite)$' { $Col.Red } default { $Col.Track } }
  $r = Px 4; $dx = $W - (Px 88)
  FillRound $g $dc ($dx - $r) ($cy - $r) ($r * 2) ($r * 2) $r
  $bx = $W - (Px 56); $br = Px 12
  $hov = ($script:hover -eq 'refresh')
  if ($hov) { FillRound $g $Col.Hover ($bx - $br) ($cy - $br) ($br * 2) ($br * 2) $br }
  $state = $g.Save()
  $g.TranslateTransform($bx, $cy); $g.RotateTransform([float]$script:spin)
  $pen = New-Object Drawing.Pen($(if ($hov -or (Busy)) { $Col.Txt } else { $Col.Sec }), (Px 1.6))
  $pen.StartCap = 'Round'; $pen.EndCap = 'Round'
  $ar = Px 6
  $g.DrawArc($pen, -$ar, -$ar, $ar * 2, $ar * 2, 20, 290)
  $ax = [float]($ar * [Math]::Cos(20 * [Math]::PI / 180)); $ay = [float]($ar * [Math]::Sin(20 * [Math]::PI / 180))
  $g.DrawLine($pen, $ax, $ay, $ax + (Px 3), $ay - (Px 1))
  $g.DrawLine($pen, $ax, $ay, $ax + (Px 0.6), $ay - (Px 3.4))
  $pen.Dispose(); $g.Restore($state)
  Reg 'refresh' ($bx - $br) ($cy - $br) ($br * 2) ($br * 2) ''
  $mx = $W - (Px 24)
  $mh = ($script:hover -eq 'menu')
  if ($mh) { FillRound $g $Col.Hover ($mx - $br) ($cy - $br) ($br * 2) ($br * 2) $br }
  $mb = New-Object Drawing.SolidBrush($(if ($mh) { $Col.Txt } else { $Col.Sec })); $dr = Px 1.7
  foreach ($o in -5.5, 0, 5.5) { $g.FillEllipse($mb, [float]($mx + (Px $o) - $dr), [float]($cy - $dr), [float]($dr * 2), [float]($dr * 2)) }
  $mb.Dispose()
  Reg 'menu' ($mx - $br) ($cy - $br) ($br * 2) ($br * 2) ''
  return $y + (Px $Lay.Header)
}

# 작은 링 + 라벨/남은 시간 (한 칸)
function Draw-MiniRing($g, [float]$x0, [float]$y, $id, $label, $row, $base) {
  $cy = $y + (Px 34); $r = Px 20
  if ($script:hover -eq $id) { FillRound $g $Col.Hover ($x0 - (Px 8)) ($y + (Px 4)) (Px 128) (Px 60) (Px 10) }
  $shown = Anim $row.Key
  Ring $g ($x0 + $r) $cy $r (Px 5) (RingColor $base $row.Pct) $shown
  T $g ('{0:0}' -f $shown) $Fnt.Pct $Col.Txt ($x0 + $r) $cy 'C'
  T $g $label $Fnt.Lbl $Col.Txt ($x0 + (Px 52)) ($cy - (Px 8))
  T $g (KoLeft $row.Ts) $Fnt.Sec $Col.Dim2 ($x0 + (Px 52)) ($cy + (Px 10))
  Reg $id ($x0 - (Px 8)) ($y + (Px 4)) (Px 128) (Px 60) ''
}

function Draw-Card($g) {
  $g.SmoothingMode = 'AntiAlias'; $g.PixelOffsetMode = 'HighQuality'
  $script:regions.Clear()
  $W = [float]$form.ClientSize.Width
  $rc = New-Object Drawing.Rectangle(0, 0, $form.ClientSize.Width, $form.ClientSize.Height)
  $gb = New-Object Drawing.Drawing2D.LinearGradientBrush($rc, $Col.GradTop, $Col.GradBot, 90.0); $g.FillRectangle($gb, $rc); $gb.Dispose()
  if ([Environment]::OSVersion.Version.Build -lt 22000) {
    $pen = New-Object Drawing.Pen($Col.Border, 1); $g.DrawRectangle($pen, 0, 0, ($form.ClientSize.Width - 1), ($form.ClientSize.Height - 1)); $pen.Dispose()
  }
  $y = Draw-Header $g $W ([float]0)
  $rows = Get-Rows
  $rw = $rows | Where-Object { $_.Key -eq 'week' } | Select-Object -First 1
  $r5 = $rows | Where-Object { $_.Key -eq 'five' } | Select-Object -First 1
  $m0 = $rows | Where-Object { $_.Id -eq 'm0' } | Select-Object -First 1

  # 큰 링: 주간
  $cx = $W / 2; $cy = $y + (Px 78); $R = Px 62
  if ($script:hover -eq 'rw') { FillRound $g $Col.Hover ($cx - (Px 100)) ($y + (Px 6)) (Px 200) (Px 168) (Px 14) }
  $shown = Anim 'week'
  Ring $g $cx $cy $R (Px 13) (RingColor $Col.Week $rw.Pct) $shown
  T $g ('{0:0}%' -f $shown) $Fnt.Big $Col.Txt $cx ($cy - (Px 6)) 'C' 44
  T $g '주간' $Fnt.Lbl $Col.Sec $cx ($cy + (Px 22)) 'C'
  T $g (ResetText $rw.Ts) $Fnt.Lbl $Col.Sec $cx ($cy + $R + (Px 24)) 'C'
  Reg 'rw' ($cx - (Px 100)) ($y + (Px 6)) (Px 200) (Px 168) ''
  $y += Px 198

  # 구분선 + 작은 링 2개 (5시간 / 최다 모델 주간)
  $dp = New-Object Drawing.Pen($Col.Div, 1)
  $g.DrawLine($dp, (Px 20), $y, ($W - (Px 20)), $y)
  Draw-MiniRing $g (Px 20) $y 'r5' '5시간' $r5 $Col.Five
  if ($m0) { Draw-MiniRing $g (Px 146) $y 'm0' ("$($m0.Label) 주간") $m0 $Col.Model }
  $y += Px 68
  $g.DrawLine($dp, (Px 20), $y, ($W - (Px 20)), $y); $dp.Dispose()

  # 크레딧 / 오늘 토큰
  $raw = "$(V 't_raw')".Split(','); $sum = 0.0
  foreach ($x in $raw) { $n = 0.0; if ([double]::TryParse($x, [ref]$n)) { $sum += $n } }
  $x1 = Px 20
  if (Has-Credit) {
    T $g '크레딧' $Fnt.Lbl $Col.Sec $x1 ($y + (Px 20))
    $val = Money (V 'cr_used'); T $g $val $Fnt.Val $Col.Txt $x1 ($y + (Px 44))
    if (Has-CreditLimit) { T $g ('/ ' + (Money (V 'cr_limit'))) $Fnt.Sec $Col.Dim2 ($x1 + (TW $val $Fnt.Val) + (Px 5)) ($y + (Px 45)) }
    $x1 = Px 146
  }
  T $g '오늘 토큰' $Fnt.Lbl $Col.Sec $x1 ($y + (Px 20))
  T $g (Human $sum) $Fnt.Val $Col.Txt $x1 ($y + (Px 44))
  $y += Px 70

  # 하단: 갱신 시각 또는 오류 상태
  $st = V 'status'
  if ($st -in 'ok', '-', 'init') { T $g (AgeText) $Fnt.Sec $Col.Dim2 ($W / 2) ($y + (Px 8)) 'C' }
  else {
    $c = if ($st -match '^(429|error)$') { $Col.Amber } else { $Col.Red }
    T $g (Status-Text) $Fnt.Sec $c ($W / 2) ($y + (Px 8)) 'C'
    if ("$(V 'err')" -ne '-') { Reg 'err' (Px 8) ($y - (Px 6)) ($W - (Px 16)) (Px 24) '' }
  }
  if ($script:flashUntil -gt [DateTime]::Now) {
    $a = [int](90 + 165 * (0.5 + 0.5 * [Math]::Sin([Environment]::TickCount / 110.0)))
    $pen = New-Object Drawing.Pen(([Drawing.Color]::FromArgb($a, $Col.Red.R, $Col.Red.G, $Col.Red.B)), (Px 3))
    $g.DrawRectangle($pen, (Px 1.5), (Px 1.5), ($form.ClientSize.Width - (Px 3)), ($form.ClientSize.Height - (Px 3))); $pen.Dispose()
  }
}

$form.Add_Paint({ param($s, $e) try { Draw-Card $e.Graphics } catch {} })


# ---- 애니메이션 --------------------------------------------------------------------------
$fast = New-Object Windows.Forms.Timer; $fast.Interval = 30
function Kick { if (-not $fast.Enabled) { $fast.Start() } }
function Busy { $null -ne $script:job -and -not $script:job.Handle.IsCompleted -and $script:job.Api }
$fast.Add_Tick({
  try {
    $moving = $false
    $keys = @(Get-Rows | ForEach-Object { $_.Key }) + @('credit')
    foreach ($key in $keys) {
      $t = Target $key; $c = Anim $key
      if ([Math]::Abs($t - $c) -gt 0.15) { $script:A[$key] = $c + ($t - $c) * 0.14; $moving = $true } else { $script:A[$key] = $t }
    }
    if ($script:flashUntil -gt [DateTime]::Now) { $moving = $true }
    if (Busy) { $script:spin = ($script:spin + 14) % 360; $moving = $true } elseif ($script:spin -ne 0) { $script:spin = 0 }
    Check-Job
    $form.Invalidate()
    if (-not $moving) { $fast.Stop() }
  } catch {}
})

# ---- 데이터 ------------------------------------------------------------------------------
function Read-Usage {
  $h = @{}
  if (Test-Path $UsageFile) {
    try { foreach ($l in [IO.File]::ReadAllLines($UsageFile)) { if ($l -match '^([a-z_]+)=(.*)$') { $h[$Matches[1]] = $Matches[2] } } } catch {}
  }
  if ($h.Count -gt 0) { $script:D = $h }
  $ms = @()
  foreach ($part in "$(V 'models')".Split(';')) {
    $f = $part.Split('|'); if ($f.Count -lt 4 -or $f[0] -eq '' -or $f[0] -eq '-') { continue }
    $ms += [pscustomobject]@{ Name = $f[0]; Pct = (ToPct $f[1]); Ts = $f[2]; Active = ($f[3] -eq '1') }
  }
  $script:Models = $ms
  Apply-Size
  try { Update-Tray } catch {}
  try { Update-Strip } catch {}
  try { if ("$(V 'status')" -eq 'ok') { Check-Alerts } } catch {}
  Kick
}

$script:job = $null
$script:rs = [runspacefactory]::CreateRunspace(); $script:rs.Open()   # 상태(증분 스캔 위치 등) 유지용
$script:fetchSrc = [IO.File]::ReadAllText($FetchScript)
function Start-Fetch([bool]$force = $false) {
  if ($script:job) { if (-not $script:job.Handle.IsCompleted) { return }; try { $script:job.PS.Dispose() } catch {} }
  $n = 0L; $apiDue = $force -or -not [int64]::TryParse("$(V 'next_api')", [ref]$n) -or $n -le (NowTs)
  $ps = [powershell]::Create(); $ps.Runspace = $script:rs
  [void]$ps.AddScript($script:fetchSrc).AddParameter('Out', $UsageFile).AddParameter('ApiInterval', [int]$Cfg.Interval).AddParameter('AutoRefresh', [bool]$Cfg.AutoRefresh)
  if ($force) { [void]$ps.AddParameter('Force', $true) }
  $script:job = @{ PS = $ps; Handle = $ps.BeginInvoke(); Read = $false; Api = $apiDue }
  if ($apiDue) { Kick }
}
function Check-Job {
  if ($script:job -and $script:job.Handle.IsCompleted -and -not $script:job.Read) {
    $script:job.Read = $true
    try { [void]$script:job.PS.EndInvoke($script:job.Handle) } catch {}
    Read-Usage
  }
}

# ---- 툴팁 / 트레이 ------------------------------------------------------------------------
$ToolTip = New-Object Windows.Forms.ToolTip
$ToolTip.UseAnimation = $true; $ToolTip.UseFading = $true

$tray = New-Object Windows.Forms.NotifyIcon
$script:trayHandle = $null
function Set-TrayIcon([double]$pct, $color) {
  $bmp = New-Object Drawing.Bitmap(32, 32)
  $g = [Drawing.Graphics]::FromImage($bmp); $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'
  $bb = New-Object Drawing.SolidBrush((C 30 32 40)); $g.FillEllipse($bb, 0, 0, 31, 31); $bb.Dispose()
  $pen = New-Object Drawing.Pen($color, 4); $g.DrawArc($pen, 3, 3, 25, 25, -90, [float](3.6 * [Math]::Max($pct, 1))); $pen.Dispose()
  $trf = New-Object Drawing.Font('Segoe UI Semibold', 11, [Drawing.GraphicsUnit]::Pixel)
  $wb = New-Object Drawing.SolidBrush((C 245 245 250))
  $g.DrawString(('{0:0}' -f $pct), $trf, $wb, (New-Object Drawing.RectangleF(0, 0, 32, 32)), $SfC); $wb.Dispose(); $trf.Dispose(); $g.Dispose()
  $h = $bmp.GetHicon(); $tray.Icon = [Drawing.Icon]::FromHandle($h)
  if ($script:trayHandle) { [void][CUW.Native]::DestroyIcon($script:trayHandle) }
  $script:trayHandle = $h; $bmp.Dispose()
}
function Update-Tray {
  $five = ToPct (V 'five'); $wk = ToPct (V 'week')
  $mx = 0.0; foreach ($m in $script:Models) { if ($m.Pct -gt $mx) { $mx = $m.Pct } }
  $t = "Claude 5h $('{0:0}' -f $five)% · 주 $('{0:0}' -f $wk)%"
  if ($script:Models.Count -gt 0) { $t += " · 모델 최대 $('{0:0}' -f $mx)%" }
  if ($t.Length -gt 63) { $t = $t.Substring(0, 63) }
  $tray.Text = $t
  Set-TrayIcon $five (PctColor ([Math]::Max($five, [Math]::Max($wk, $mx))))
}


# ---- 알림: 경고(85%) 토스트 / 위험(95%) 토스트+위젯 깜빡임 / 속도 예측 / 추가 크레딧 --------------------
$script:flashUntil = [DateTime]::MinValue
$script:hist = @{}          # key -> List of @(unixTime, pct)  (속도 계산용, 최근 90분)
$script:lastCreditNote = [DateTime]::MinValue
function Notified($k) { ";$($Cfg.Notified);" -like "*;$k;*" }
function Mark($k) {
  $list = @("$($Cfg.Notified)".Split(';') | Where-Object { $_ }) + $k
  if ($list.Count -gt 60) { $list = $list[($list.Count - 60)..($list.Count - 1)] }
  $Cfg.Notified = $list -join ';'; Save-Settings
}
function Toast($title, $text, [bool]$danger) {
  if (-not $Cfg.Alerts) { return }
  if ($title.Length -gt 60) { $title = $title.Substring(0, 60) }
  if ($text.Length -gt 250) { $text = $text.Substring(0, 250) }
  $icon = if ($danger) { [Windows.Forms.ToolTipIcon]::Error } else { [Windows.Forms.ToolTipIcon]::Warning }
  $tray.ShowBalloonTip(10000, $title, $text, $icon)
}
function Flash-Widget {
  if (-not $Cfg.Alerts) { return }
  $script:flashUntil = [DateTime]::Now.AddSeconds(6)
  $form.Show(); $form.TopMost = $true
  [void][CUW.Native]::SetWindowPos($form.Handle, [IntPtr](-1), 0, 0, 0, 0, 0x0013)
  Kick
}
function Check-Alerts {
  $now = NowTs
  foreach ($row in (Get-Rows)) {
    $p = [double]$row.Pct; $ts = "$($row.Ts)"; $name = if ($row.Key -eq 'five') { '5시간' } elseif ($row.Key -eq 'week') { '주간' } else { "$($row.Label) 주간" }
    $left = LeftFromTs $ts
    # 1) 기준치 알림 (리셋 주기마다 단계별 1회)
    if ($p -ge 100 -and -not (Notified "$($row.Key)|$ts|full")) {
      Mark "$($row.Key)|$ts|full"; Mark "$($row.Key)|$ts|alert"; Mark "$($row.Key)|$ts|warn"
      $extra = if (Has-Credit) { ' 지금부터는 추가 사용 크레딧(유료)으로 넘어갈 수 있어요.' } else { '' }
      Toast "$name 한도 도달" "리셋: $left.$extra" $true; Flash-Widget
    }
    elseif ($p -ge [double]$Cfg.AlertPct -and -not (Notified "$($row.Key)|$ts|alert")) {
      Mark "$($row.Key)|$ts|alert"; Mark "$($row.Key)|$ts|warn"
      Toast "$name 한도 $('{0:0}' -f $p)%" "곧 한도에 걸립니다 · 리셋: $left" $true; Flash-Widget
    }
    elseif ($p -ge [double]$Cfg.WarnPct -and -not (Notified "$($row.Key)|$ts|warn")) {
      Mark "$($row.Key)|$ts|warn"
      Toast "$name 한도 $('{0:0}' -f $p)%" "리셋: $left" $false
    }
    # 2) 속도 예측: 최근 10~90분 기울기로 한도 도달 시점 추정
    if (-not $script:hist.ContainsKey($row.Key)) { $script:hist[$row.Key] = New-Object System.Collections.ArrayList }
    $h = $script:hist[$row.Key]
    if ($h.Count -gt 0 -and [double]$h[$h.Count - 1][1] -gt $p + 5) { $h.Clear() }          # 리셋됨
    [void]$h.Add(@($now, $p))
    while ($h.Count -gt 0 -and $now - [int64]$h[0][0] -gt 5400) { $h.RemoveAt(0) }
    if ($Cfg.PaceWarn -and $p -ge 50 -and $p -lt [double]$Cfg.AlertPct -and $h.Count -ge 2) {
      $t0 = [int64]$h[0][0]; $p0 = [double]$h[0][1]; $dt = $now - $t0
      if ($dt -ge 600 -and $p -gt $p0) {
        $eta = (100 - $p) / (($p - $p0) / $dt)
        $n = 0L; $toReset = if ([int64]::TryParse($ts, [ref]$n)) { $n - $now } else { [int64]::MaxValue }
        if ($eta -lt 3600 -and $eta -lt $toReset -and -not (Notified "$($row.Key)|$ts|pace")) {
          Mark "$($row.Key)|$ts|pace"
          $m = [Math]::Max(1, [Math]::Round($eta / 60))
          Toast "이 속도면 약 $($m)분 뒤 $name 한도" "지금 $('{0:0}' -f $p)% · 리셋: $left" $false
        }
      }
    }
  }
  # 3) 추가 사용 크레딧: 금액이 늘어나면 알림 (30분에 최대 1번)
  if (Has-Credit) {
    $u = 0.0; [void][double]::TryParse("$(V 'cr_used')", [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$u)
    $seen = [double]$Cfg.CreditSeen
    if ($seen -lt 0 -or $u -lt $seen) { $Cfg.CreditSeen = $u; Save-Settings }          # 첫 실행 / 월 초기화
    elseif ($u -gt $seen + 0.004 -and $Cfg.CreditAlert -and [DateTime]::Now -gt $script:lastCreditNote.AddMinutes(30)) {
      $script:lastCreditNote = [DateTime]::Now
      Toast "추가 사용 크레딧 사용 중" "이번 달 $(Money $u) (+$(Money ($u - $seen))). 한도를 넘긴 사용분은 유료입니다." $true
      $Cfg.CreditSeen = $u; Save-Settings
    }
  }
}
$tray.Add_BalloonTipClicked({ $form.Show(); Flash-Widget })

# ---- 메뉴 --------------------------------------------------------------------------------
$script:menu = New-Object Windows.Forms.ContextMenuStrip
$menu.ShowCheckMargin = $true; $menu.ShowImageMargin = $false
$mi = $menu.Items.Add('지금 갱신'); $mi.Add_Click({ Start-Fetch $true })
$miTheme = New-Object Windows.Forms.ToolStripMenuItem('테마')
foreach ($z in @(@('light', '라이트'), @('dark', '다크'))) {
  $it = New-Object Windows.Forms.ToolStripMenuItem($z[1]); $it.Tag = $z[0]
  $it.Add_Click({ param($s) $Cfg.Theme = "$($s.Tag)"; Save-Settings; Set-Theme $Cfg.Theme; try { Update-Tray } catch {} }); [void]$miTheme.DropDownItems.Add($it)
}
[void]$menu.Items.Add($miTheme)
[void]$menu.Items.Add('-')
$miZ = New-Object Windows.Forms.ToolStripMenuItem('표시 방식')
foreach ($z in @(@('desktop', '바탕화면에 두기 (다른 창 뒤)'), @('normal', '일반 창'), @('top', '항상 위'))) {
  $it = New-Object Windows.Forms.ToolStripMenuItem($z[1]); $it.Tag = $z[0]
  $it.Add_Click({ param($s) $Cfg.ZMode = "$($s.Tag)"; Save-Settings; Apply-ZOrder }); [void]$miZ.DropDownItems.Add($it)
}
[void]$menu.Items.Add($miZ)
$miInt = New-Object Windows.Forms.ToolStripMenuItem('한도 조회 주기')
foreach ($v in 120, 180, 300, 600) {
  $it = New-Object Windows.Forms.ToolStripMenuItem("$([int]($v / 60))분"); $it.Tag = $v
  $it.Add_Click({ param($s) $Cfg.Interval = [int]$s.Tag; Save-Settings }); [void]$miInt.DropDownItems.Add($it)
}
[void]$menu.Items.Add($miInt)
$miOp = New-Object Windows.Forms.ToolStripMenuItem('투명도')
foreach ($v in 1.0, 0.96, 0.85, 0.7) {
  $it = New-Object Windows.Forms.ToolStripMenuItem("$([int]($v * 100))%"); $it.Tag = $v
  $it.Add_Click({ param($s) $Cfg.Opacity = [double]$s.Tag; $form.Opacity = $Cfg.Opacity; Save-Settings }); [void]$miOp.DropDownItems.Add($it)
}
[void]$menu.Items.Add($miOp)
$miRef = New-Object Windows.Forms.ToolStripMenuItem('만료된 토큰 자동 갱신')
$miRef.Add_Click({ $Cfg.AutoRefresh = -not $Cfg.AutoRefresh; Save-Settings }); [void]$menu.Items.Add($miRef)
$miAl = New-Object Windows.Forms.ToolStripMenuItem('알림')
$miAlOn = New-Object Windows.Forms.ToolStripMenuItem('알림 켜기'); $miAlOn.Add_Click({ $Cfg.Alerts = -not $Cfg.Alerts; Save-Settings }); [void]$miAl.DropDownItems.Add($miAlOn)
[void]$miAl.DropDownItems.Add('-')
foreach ($z in @(@(80, 95), @(85, 95), @(90, 98))) {
  $it = New-Object Windows.Forms.ToolStripMenuItem("경고 $($z[0])% · 위험 $($z[1])%"); $it.Tag = "$($z[0]),$($z[1])"
  $it.Add_Click({ param($s) $v = "$($s.Tag)".Split(','); $Cfg.WarnPct = [int]$v[0]; $Cfg.AlertPct = [int]$v[1]; Save-Settings }); [void]$miAl.DropDownItems.Add($it)
}
[void]$miAl.DropDownItems.Add('-')
$miPace = New-Object Windows.Forms.ToolStripMenuItem('사용 속도 예측 알림'); $miPace.Add_Click({ $Cfg.PaceWarn = -not $Cfg.PaceWarn; Save-Settings }); [void]$miAl.DropDownItems.Add($miPace)
$miCr = New-Object Windows.Forms.ToolStripMenuItem('추가 크레딧 사용 알림'); $miCr.Add_Click({ $Cfg.CreditAlert = -not $Cfg.CreditAlert; Save-Settings }); [void]$miAl.DropDownItems.Add($miCr)
[void]$miAl.DropDownItems.Add('-')
$mi = $miAl.DropDownItems.Add('알림 테스트'); $mi.Add_Click({ $old = $Cfg.Alerts; $Cfg.Alerts = $true; Toast '5시간 한도 95%' '알림 테스트입니다 · 실제 한도가 이 정도면 이렇게 알려 드려요.' $true; Flash-Widget; $Cfg.Alerts = $old })
[void]$menu.Items.Add($miAl)
$miStrip = New-Object Windows.Forms.ToolStripMenuItem('작업표시줄에 요약 표시')
$miStrip.Add_Click({ $Cfg.TaskbarStrip = -not $Cfg.TaskbarStrip; Save-Settings; Update-Strip }); [void]$menu.Items.Add($miStrip)
$miAuto = New-Object Windows.Forms.ToolStripMenuItem('Windows 시작 시 실행')
$miAuto.Add_Click({ Set-AutoStart (-not (Test-AutoStart)) }); [void]$menu.Items.Add($miAuto)
[void]$menu.Items.Add('-')
$mi = $menu.Items.Add('오류 로그 열기'); $mi.Add_Click({ $lp = Join-Path $DataDir 'fetch.log'; if (Test-Path $lp) { Start-Process notepad.exe $lp } })
$mi = $menu.Items.Add('데이터 폴더 열기'); $mi.Add_Click({ Start-Process explorer.exe $DataDir })
$mi = $menu.Items.Add('종료'); $mi.Add_Click({ $form.Close() })
$menu.Add_Opening({
  foreach ($i in $miTheme.DropDownItems) { $i.Checked = ("$($i.Tag)" -eq "$($Cfg.Theme)") }
  $miStrip.Checked = [bool]$Cfg.TaskbarStrip; $miRef.Checked = [bool]$Cfg.AutoRefresh; $miAuto.Checked = Test-AutoStart
  $miAlOn.Checked = [bool]$Cfg.Alerts; $miPace.Checked = [bool]$Cfg.PaceWarn; $miCr.Checked = [bool]$Cfg.CreditAlert
  foreach ($i in $miAl.DropDownItems) { if ($i.Tag) { $i.Checked = ("$($i.Tag)" -eq "$($Cfg.WarnPct),$($Cfg.AlertPct)") } }
  foreach ($i in $miZ.DropDownItems)   { $i.Checked = ("$($i.Tag)" -eq "$($Cfg.ZMode)") }
  foreach ($i in $miInt.DropDownItems) { $i.Checked = ([int]$i.Tag -eq [int]$Cfg.Interval) }
  foreach ($i in $miOp.DropDownItems)  { $i.Checked = ([Math]::Abs([double]$i.Tag - [double]$Cfg.Opacity) -lt 0.001) }
})
$form.ContextMenuStrip = $menu
$tray.ContextMenuStrip = $menu
$tray.Add_MouseClick({ param($s, $e) if ($e.Button -eq 'Left') { $form.Show(); $form.Activate(); Kick } })

# ---- 작업표시줄 요약: 트레이 왼쪽에 "5시간 · 주간 · 모델" 숫자를 겹쳐 띄우는 작은 창 -----------------------
# Windows 에는 작업표시줄에 글자를 넣는 공식 방법이 없어, 테두리 없는 작은 창을 트레이 옆에 맞춰 둔다.
$strip = New-Object Windows.Forms.Form
$strip.FormBorderStyle = 'None'; $strip.ShowInTaskbar = $false; $strip.StartPosition = 'Manual'; $strip.TopMost = $true
$strip.GetType().GetProperty('DoubleBuffered', [Reflection.BindingFlags]'NonPublic,Instance').SetValue($strip, $true, $null)
$strip.ClientSize = New-Object Drawing.Size((PxI 120), (PxI 40))
$FntStrip = New-Object Drawing.Font('Segoe UI Semibold', 10.5)
$script:stripInit = $false; $script:stripKey = $null

function Taskbar-IsLight {
  try { [int](Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name SystemUsesLightTheme -ErrorAction Stop).SystemUsesLightTheme -eq 1 } catch { $false }
}
function Strip-Values {
  $v = @(@{ P = (ToPct (V 'five')); Base = $Col.Five }, @{ P = (ToPct (V 'week')); Base = $Col.Week })
  if ($script:Models.Count -gt 0) { $v += @{ P = [double]$script:Models[0].Pct; Base = $Col.Model } }
  , $v
}
function Update-Strip {
  if (-not $Cfg.TaskbarStrip) { if ($strip.Visible) { $strip.Hide() }; return }
  $ns = 0; [void][CUW.Native]::SHQueryUserNotificationState([ref]$ns)
  $tb = [CUW.Native]::FindWindow('Shell_TrayWnd', $null)
  $r = New-Object 'int[]' 4
  if ($ns -in 2, 3, 4 -or $tb -eq [IntPtr]::Zero -or -not [CUW.Native]::GetWindowRect($tb, $r)) { if ($strip.Visible) { $strip.Hide() }; return }
  $tl = $r[0]; $tt = $r[1]; $tw = $r[2] - $r[0]; $th = $r[3] - $r[1]
  if ($th -gt $tw) { if ($strip.Visible) { $strip.Hide() }; return }                     # 세로 작업표시줄은 미지원
  $right = $r[2] - (PxI 8)
  $nw = [CUW.Native]::FindWindowEx($tb, [IntPtr]::Zero, 'TrayNotifyWnd', $null); $nr = New-Object 'int[]' 4
  if ($nw -ne [IntPtr]::Zero -and [CUW.Native]::GetWindowRect($nw, $nr) -and $nr[0] -gt $tl) { $right = $nr[0] }
  $vals = Strip-Values
  $w = (PxI 20); foreach ($x in $vals) { $w += (TW ('{0:0}' -f $x.P) $FntStrip) }; $w += (PxI 22) * ($vals.Count - 1)
  $light = Taskbar-IsLight
  $key = if ($light) { C 254 254 253 } else { C 1 1 2 }
  if (-not $script:stripKey -or $script:stripKey -ne $key) { $strip.BackColor = $key; $strip.TransparencyKey = $key; $script:stripKey = $key }
  $script:stripLight = $light
  if (-not $script:stripInit) {
    $script:stripInit = $true
    $ex = [CUW.Native]::GetWindowLong($strip.Handle, -20)
    [void][CUW.Native]::SetWindowLong($strip.Handle, -20, ($ex -bor 0x08000080))          # NOACTIVATE + TOOLWINDOW
  }
  [void][CUW.Native]::SetWindowPos($strip.Handle, [IntPtr](-1), ($right - $w), $tt, $w, $th, 0x0050)   # TOPMOST, 활성화 없이 표시
  $tip = '5시간 · 주간' + $(if ($script:Models.Count -gt 0) { " · $($script:Models[0].Name) 주간" } else { '' })
  if ($ToolTip.GetToolTip($strip) -ne $tip) { $ToolTip.SetToolTip($strip, $tip) }
  $strip.Invalidate()
}
function Draw-Strip($g) {
  $g.Clear($script:stripKey)
  $H = [float]$strip.ClientSize.Height; $cy = $H / 2
  $txt = if ($script:stripLight) { C 96 100 112 } else { C 170 172 186 }
  $x = Px 10; $first = $true
  foreach ($v in (Strip-Values)) {
    if (-not $first) { T $g '·' $FntStrip $txt ($x + (Px 8)) $cy 'C'; $x += Px 22 }
    $first = $false
    $s = '{0:0}' -f $v.P
    T $g $s $FntStrip (RingColor $v.Base $v.P) $x $cy
    $x += TW $s $FntStrip
  }
}
$strip.Add_Paint({ param($s, $e) try { Draw-Strip $e.Graphics } catch {} })
$strip.ContextMenuStrip = $menu
$strip.Add_MouseUp({ param($s, $e) if ($e.Button -eq 'Left') { $form.Show(); $form.Activate(); Kick } })

# ---- 마우스 --------------------------------------------------------------------------------
function HitTest($pt) { for ($i = $script:regions.Count - 1; $i -ge 0; $i--) { $r = $script:regions[$i]; if ($r.R.Contains([float]$pt.X, [float]$pt.Y)) { return $r } }; $null }
$script:down = $null
$form.Add_MouseDown({ param($s, $e) if ($e.Button -eq 'Left') { $script:down = $e.Location } })
$form.Add_MouseMove({ param($s, $e)
  if ($script:down -and $e.Button -eq 'Left') {
    if ([Math]::Abs($e.X - $script:down.X) + [Math]::Abs($e.Y - $script:down.Y) -gt 4) {
      $script:down = $null
      [void][CUW.Native]::ReleaseCapture()
      [void][CUW.Native]::SendMessage($form.Handle, 0xA1, [IntPtr]2, [IntPtr]::Zero)   # 창 이동
      $Cfg.X = $form.Left; $Cfg.Y = $form.Top; Save-Settings
    }
    return
  }
  $r = HitTest $e.Location
  $id = if ($r) { $r.Id } else { '' }
  if ($id -ne $script:hover) {
    $script:hover = $id
    $form.Cursor = if ($id -eq 'refresh' -or $id -eq 'menu' -or $id -eq 'err' -or $id -match '^(r5|rw|m\d+)$') { [Windows.Forms.Cursors]::Hand } else { [Windows.Forms.Cursors]::Default }
    $form.Invalidate()
  }
})
$form.Add_MouseLeave({ if ($script:hover -ne '') { $script:hover = ''; $form.Invalidate() } })
$form.Add_MouseUp({ param($s, $e)
  if ($e.Button -ne 'Left' -or -not $script:down) { return }
  $script:down = $null
  $r = HitTest $e.Location; if (-not $r) { return }
  switch ($r.Id) {
    'refresh' { Start-Fetch $true }
    'menu'    { $script:menu.Show($form, $e.Location) }
    'err'     { try { [Windows.Forms.Clipboard]::SetText("$(V 'err')") } catch {} }
    { $_ -match '^(r5|rw|m\d+)$' } { $Cfg.ShowAbs = -not $Cfg.ShowAbs; Save-Settings; $form.Invalidate() }
  }
})
$form.Add_Deactivate({ if ("$($Cfg.ZMode)" -eq 'desktop') { Apply-ZOrder } })

# ---- 1초 타이머: 카운트다운, 로컬 토큰 10초, API 는 설정 주기 --------------------------------------
$script:tick = 0
$timer = New-Object Windows.Forms.Timer; $timer.Interval = 1000
$timer.Add_Tick({
  try {
    $script:tick++
    Check-Job
    if ($script:tick % 10 -eq 0) { Start-Fetch $false }
    if ($script:tick % 3 -eq 0) { Apply-ZOrder }
    Update-Strip
    if (-not $fast.Enabled) { $form.Invalidate() }     # 남은 시간 카운트다운
  } catch {}
})

$form.Add_Shown({
  try {
    $ex = [CUW.Native]::GetWindowLong($form.Handle, -20)
    [void][CUW.Native]::SetWindowLong($form.Handle, -20, (($ex -bor 0x80) -band (-bnot 0x40000)))   # TOOLWINDOW (Alt+Tab 제외)
    $pref = 2; [void][CUW.Native]::DwmSetWindowAttribute($form.Handle, 33, [ref]$pref, 4)            # Win11 둥근 모서리
  } catch {}
  try { Set-TrayIcon 0 $Col.Dim } catch {}
  $tray.Visible = $true
  Read-Usage
  Apply-ZOrder
  Start-Fetch $true
  $timer.Start(); Kick
})
$form.Add_FormClosed({
  $timer.Stop(); $fast.Stop(); $tray.Visible = $false; $tray.Dispose(); try { $strip.Close() } catch {}
  if ($script:trayHandle) { [void][CUW.Native]::DestroyIcon($script:trayHandle) }
  try { $script:rs.Close() } catch {}
  try { $mutex.ReleaseMutex() } catch {}
})

$form.ClientSize = New-Object Drawing.Size((PxI $BaseW), (PxI (Get-Height)))
Place-Initial
Keep-OnScreen
[Windows.Forms.Application]::Run($form)
