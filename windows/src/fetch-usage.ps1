# Claude Code usage collector for ClaudeUsageWidget.
# - Plan limits : GET https://api.anthropic.com/api/oauth/usage (undocumented, same source as /usage)
#                 called at most once per -ApiInterval seconds; 429 -> backs off (Retry-After, min 5 min)
# - Token usage : today's assistant messages in ~/.claude/projects/**/*.jsonl, read incrementally
# Writes key=value lines (fixed order) to usage.txt; widget.ps1 reads it.
# State lives in $global:CUW, so running it repeatedly in the same runspace is cheap.
# If the OAuth access token is expired and -AutoRefresh is set, it is refreshed with the refresh token
# and written back to .credentials.json (only if nobody else changed the file meanwhile).

param(
  [string]$Out = (Join-Path $PSScriptRoot 'usage.txt'),
  [int]$ApiInterval = 180,
  [switch]$Force,
  [bool]$AutoRefresh = $true
)

$ErrorActionPreference = 'Stop'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$cfg = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $env:USERPROFILE '.claude' }
$inv = [Globalization.CultureInfo]::InvariantCulture
$ClientId = '9d1c250a-e61b-44d9-88ed-5944d1962f5e'   # Claude Code's public OAuth client id

$today = [DateTime]::Today
if (-not $global:CUW -or $global:CUW.Day -ne $today) {
  $prevNext = if ($global:CUW) { $global:CUW.NextApi } else { [DateTime]::MinValue }
  $global:CUW = @{
    Day = $today; NextApi = $prevNext; Files = @{}
    Seen = (New-Object 'System.Collections.Generic.HashSet[string]')
    In = [int64]0; Out = [int64]0; Cw = [int64]0; Cr = [int64]0; N = [int64]0
  }
}
$st = $global:CUW

# ---- defaults / previous values (kept when the API is skipped or fails) ---------------
$d = [ordered]@{
  status = 'init'; plan = '-'; tier = '-'; api_ts = ''
  five = '0'; five_left = '-'; five_at = '-'
  week = '0'; week_left = '-'; week_at = '-'
  sc_name = '-'; sc = '0'; sc_left = '-'
  active = '-'
  t_total = '0'; t_in = '0'; t_out = '0'; t_cw = '0'; t_cr = '0'; t_msgs = '0'
  updated = '-'; api_at = '-'; five_ts = ''; week_ts = ''; sc_ts = ''
  models = ''; next_api = ''; t_raw = '0,0,0,0'; err = ''
  cr_on = ''; cr_used = ''; cr_limit = ''; cr_cur = ''; cr_pct = ''
}
if (Test-Path $Out) {
  foreach ($l in [IO.File]::ReadAllLines($Out)) {
    if ($l -match '^([a-z_]+)=(.*)$' -and $d.Contains($Matches[1])) { $d[$Matches[1]] = $Matches[2] }
  }
}

function ToDto($v) {
  if ($null -eq $v -or "$v" -eq '') { return $null }
  if ($v -is [datetime]) { return [DateTimeOffset]$v }
  $n = 0L; if ([int64]::TryParse("$v", [ref]$n)) { return [DateTimeOffset]::FromUnixTimeSeconds($n) }
  return [DateTimeOffset]::Parse("$v", $inv)
}
function LeftStr($v) {
  $t = ToDto $v; if (-not $t) { return '-' }
  $s = $t - [DateTimeOffset]::Now
  if ($s.TotalSeconds -le 0) { return 'now' }
  if ($s.TotalDays -ge 1)  { return ('{0}d{1}h' -f [int][math]::Floor($s.TotalDays), $s.Hours) }
  if ($s.TotalHours -ge 1) { return ('{0}h{1:00}m' -f [int][math]::Floor($s.TotalHours), $s.Minutes) }
  return ('{0}m' -f [int][math]::Ceiling($s.TotalMinutes))
}
function AtStr($v) { $t = ToDto $v; if (-not $t) { return '-' }; $t.ToLocalTime().ToString('MM/dd HH:mm', $inv) }
function TsStr($v) { $t = ToDto $v; if (-not $t) { return '' }; "$($t.ToUnixTimeSeconds())" }
function Pct($v) { if ($null -eq $v -or "$v" -eq '') { return '0' }; [string][int][math]::Round([double]$v) }
function Human([int64]$n) {
  if ($n -ge 1e9) { return ('{0:0.00}B' -f ($n / 1e9)) }
  if ($n -ge 1e6) { return ('{0:0.0}M'  -f ($n / 1e6)) }
  if ($n -ge 1e3) { return ('{0:0.0}K'  -f ($n / 1e3)) }
  return "$n"
}
function HttpCode($err) { try { return [int]$err.Exception.Response.StatusCode } catch { return $null } }
function RetryAfter($err) {
  try { $h = $err.Exception.Response.Headers['Retry-After']; if ($h) { return [int]$h } } catch {}                  # PS 5.1
  try { $ra = $err.Exception.Response.Headers.RetryAfter; if ($ra.Delta) { return [int]$ra.Delta.TotalSeconds } } catch {}  # PS 7
  return 0
}
function ErrBody($err) {
  try { if ($err.ErrorDetails -and $err.ErrorDetails.Message) { return "$($err.ErrorDetails.Message)" } } catch {}
  try { $rs = $err.Exception.Response.GetResponseStream(); $rs.Position = 0; return (New-Object IO.StreamReader($rs)).ReadToEnd() } catch {}
  return ''
}
function ErrText($stage, $err) {
  $c = HttpCode $err; $b = (ErrBody $err) -replace '\s+', ' '
  if ($b.Length -gt 200) { $b = $b.Substring(0, 200) }
  $t = "${stage}: " + $(if ($c) { "HTTP $c " } else { '' }) + "$($err.Exception.Message)" + $(if ($b) { " | $b" } else { '' })
  ($t -replace '(sk-ant-[A-Za-z0-9_-]{6})[A-Za-z0-9_-]+', '$1***' -replace '[\r\n=]', ' ')
}
function Log($line) {
  try {
    $lp = Join-Path (Split-Path -Parent $Out) 'fetch.log'
    $lines = New-Object 'System.Collections.Generic.List[string]'
    if (Test-Path $lp) { foreach ($x in @([IO.File]::ReadAllLines($lp) | Select-Object -Last 199)) { $lines.Add($x) } }
    $lines.Add(("{0} {1}" -f (Get-Date).ToString('MM-dd HH:mm:ss'), $line))
    [IO.File]::WriteAllLines($lp, $lines.ToArray())
  } catch {}
}
# overwrite in place (works for hidden files and files Claude Code keeps open)
function WriteInPlace($path, $text) {
  $bytes = (New-Object Text.UTF8Encoding $false).GetBytes($text)
  $fs = [IO.File]::Open($path, [IO.FileMode]::Truncate, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite)
  try { $fs.Write($bytes, 0, $bytes.Length); $fs.Flush() } finally { $fs.Dispose() }
}
function WriteAtomic($path, $text) {
  $tmp = "$path.tmp"
  [IO.File]::WriteAllText($tmp, $text, (New-Object Text.UTF8Encoding $false))
  Move-Item -LiteralPath $tmp -Destination $path -Force
}

function Refresh-Token($credPath, $o) {
  if (-not $o.refreshToken) { throw 'expired' }
  $body = @{ grant_type = 'refresh_token'; refresh_token = "$($o.refreshToken)"; client_id = $ClientId } | ConvertTo-Json -Compress
  $resp = $null; $errs = @()
  foreach ($u in 'https://platform.claude.com/v1/oauth/token', 'https://console.anthropic.com/v1/oauth/token') {
    try { $resp = Invoke-RestMethod -Method Post -Uri $u -Body $body -ContentType 'application/json' -TimeoutSec 20 -UserAgent 'claude-usage-widget/1.2'; break }
    catch {
      $c = HttpCode $_; $errs += (ErrText ("refresh " + ([uri]$u).Host) $_)
      if ($c -eq 400 -or $c -eq 401) { Log ($errs -join ' || '); throw 'auth' }
    }
  }
  if (-not $resp -or -not $resp.access_token) { $script:errDetail = ($errs -join ' || '); if (-not $script:errDetail) { $script:errDetail = 'refresh: no access_token in response' }; throw 'refreshfail' }

  # re-read right before writing: if Claude Code refreshed in the meantime, keep its tokens
  $raw = [IO.File]::ReadAllText($credPath)
  $j = $raw | ConvertFrom-Json
  if ("$($j.claudeAiOauth.refreshToken)" -ne "$($o.refreshToken)") { return $j.claudeAiOauth }
  $bak = "$credPath.widget-bak"
  if (-not (Test-Path $bak)) { [IO.File]::WriteAllText($bak, $raw, (New-Object Text.UTF8Encoding $false)) }
  $j.claudeAiOauth.accessToken = "$($resp.access_token)"
  if ($resp.refresh_token) { $j.claudeAiOauth.refreshToken = "$($resp.refresh_token)" }
  $exp = if ($resp.expires_in) { [double]$resp.expires_in } else { 3600 }
  $j.claudeAiOauth.expiresAt = [DateTimeOffset]::UtcNow.AddSeconds($exp).ToUnixTimeMilliseconds()
  $json = $j | ConvertTo-Json -Depth 32 -Compress
  try { WriteInPlace $credPath $json }
  catch { $script:errDetail = ErrText 'write credentials' $_; throw 'credwrite' }
  Log 'token refreshed and saved'
  return $j.claudeAiOauth
}

# ---- 1) plan limits ------------------------------------------------------------------
$now = [DateTime]::Now
# 재시작 직후에도 직전 429/오류 백오프를 이어받음 (usage.txt 의 next_api)
if (-not $st.ContainsKey('Restored')) {
  $st.Restored = $true; $st.LastForce = [DateTime]::MinValue
  $nx = 0L
  if ($d.status -in '429', 'error' -and [int64]::TryParse("$($d.next_api)", [ref]$nx) -and $nx -gt 0) {
    $st.NextApi = [DateTimeOffset]::FromUnixTimeSeconds($nx).LocalDateTime
  }
}
# 수동 갱신도 429 백오프 중에는 무시, 그 외에도 15초에 한 번까지만
$forceOk = $Force -and -not ($d.status -eq '429' -and $now -lt $st.NextApi) -and $now -ge $st.LastForce.AddSeconds(15)
if ($forceOk) { $st.LastForce = $now }
if ($forceOk -or $now -ge $st.NextApi) {
  $st.NextApi = $now.AddSeconds([Math]::Max(120, $ApiInterval))
  try {
    $script:errDetail = ''
    $credPath = Join-Path $cfg '.credentials.json'
    if (-not (Test-Path $credPath)) { throw 'nocred' }
    $o = ([IO.File]::ReadAllText($credPath) | ConvertFrom-Json).claudeAiOauth
    if (-not $o -or -not $o.accessToken) { throw 'nocred' }
    if ($o.subscriptionType) { $d.plan = "$($o.subscriptionType)" }
    if ($o.rateLimitTier) { $d.tier = "$($o.rateLimitTier)" }
    $expired = $o.expiresAt -and ([DateTimeOffset]::FromUnixTimeMilliseconds([int64]$o.expiresAt) -lt [DateTimeOffset]::UtcNow.AddSeconds(60))
    if ($expired) { if ($AutoRefresh) { $o = Refresh-Token $credPath $o } else { throw 'expired' } }

    $call = { param($tok) Invoke-RestMethod -Uri 'https://api.anthropic.com/api/oauth/usage' -TimeoutSec 15 -UserAgent 'claude-usage-widget/1.1' `
                -Headers @{ 'Authorization' = "Bearer $tok"; 'anthropic-beta' = 'oauth-2025-04-20' } }
    try { $r = & $call $o.accessToken }
    catch {
      # token looked valid but was rejected -> one refresh attempt
      if ((HttpCode $_) -eq 401 -and $AutoRefresh -and -not $expired) { $o = Refresh-Token $credPath $o; $r = & $call $o.accessToken } else { throw }
    }

    $lims = @($r.limits | Where-Object { $_ })
    $ses = $lims | Where-Object { $_.kind -eq 'session' }    | Select-Object -First 1
    $wal = $lims | Where-Object { $_.kind -eq 'weekly_all' } | Select-Object -First 1

    # five_hour / seven_day, falling back to limits[] when those objects are null
    $fu = $r.five_hour.utilization; $fr = $r.five_hour.resets_at
    if ($null -eq $fu -and $ses) { $fu = $ses.percent; $fr = $ses.resets_at }
    $wu = $r.seven_day.utilization; $wr = $r.seven_day.resets_at
    if ($null -eq $wu -and $wal) { $wu = $wal.percent; $wr = $wal.resets_at }
    $d.five = Pct $fu; $d.five_ts = TsStr $fr; $d.five_at = AtStr $fr
    $d.week = Pct $wu; $d.week_ts = TsStr $wr; $d.week_at = AtStr $wr

    $d.sc_name = '-'; $d.sc = '0'; $d.sc_ts = ''; $d.active = '-'; $d.models = ''
    $sc = $lims | Where-Object { $_.kind -eq 'weekly_scoped' } | Sort-Object { [double]$_.percent } -Descending | Select-Object -First 1
    if ($sc) {
      $nm = "$($sc.scope.model.display_name)"; if (-not $nm) { $nm = 'model' }
      $d.sc_name = ($nm -replace '[\r\n=]', ' '); $d.sc = Pct $sc.percent; $d.sc_ts = TsStr $sc.resets_at
    }
    # all per-model weekly caps: name|percent|resets_ts|active ; ...
    $d.models = (@($lims | Where-Object { $_.kind -eq 'weekly_scoped' } | Sort-Object { [double]$_.percent } -Descending) | ForEach-Object {
      $nm = ("$($_.scope.model.display_name)" -replace '[\r\n=|;]', ' '); if (-not $nm) { $nm = 'model' }
      '{0}|{1}|{2}|{3}' -f $nm, (Pct $_.percent), (TsStr $_.resets_at), $(if ($_.is_active) { 1 } else { 0 })
    }) -join ';'
    $act = $lims | Where-Object { $_.is_active } | Select-Object -First 1
    if ($act) {
      $d.active = switch ("$($act.kind)") {
        'session'       { '5h' }
        'weekly_all'    { 'week' }
        'weekly_scoped' { ("$($act.scope.model.display_name)" -replace '[\r\n=]', ' ') }
        default         { "$($act.kind)" }
      }
    }
    # extra usage (usage credits): amounts are in minor units (cents) -> divide by 10^decimal_places
    $d.cr_on = ''; $d.cr_used = ''; $d.cr_limit = ''; $d.cr_cur = ''; $d.cr_pct = ''
    $ex = $r.extra_usage
    if ($ex) {
      $dp = 2; if ($null -ne $ex.decimal_places) { $dp = [int]$ex.decimal_places }
      $div = [Math]::Pow(10, $dp)
      $d.cr_on = $(if ($ex.is_enabled) { '1' } else { '0' })
      if ($null -ne $ex.used_credits)  { $d.cr_used  = ([double]$ex.used_credits / $div).ToString('0.00', $inv) }
      if ($null -ne $ex.monthly_limit) { $d.cr_limit = ([double]$ex.monthly_limit / $div).ToString('0.00', $inv) }
      $d.cr_cur = $(if ($ex.currency) { "$($ex.currency)" } else { 'USD' })
      if ($null -ne $ex.utilization) { $d.cr_pct = Pct $ex.utilization }
      elseif ($ex.monthly_limit -and [double]$ex.monthly_limit -gt 0) { $d.cr_pct = Pct (100.0 * [double]$ex.used_credits / [double]$ex.monthly_limit) }
    }
    try { WriteAtomic (Join-Path (Split-Path -Parent $Out) 'usage-raw.json') ($r | ConvertTo-Json -Depth 20) } catch {}   # 응답 원본 (토큰 없음, 확인용)
    $st.Backoff = 0; $d.err = ''; $d.status = 'ok'; $d.api_at = $now.ToString('HH:mm:ss', $inv); $d.api_ts = "$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
  }
  catch {
    $msg = "$($_.Exception.Message)"; $code = HttpCode $_
    $d.err = if ($script:errDetail) { $script:errDetail } else { ErrText 'usage' $_ }
    Log "[$msg] $($d.err)"
    $d.status = if ($msg -in 'nocred', 'expired', 'auth', 'error') { $msg }
                elseif ($msg -eq 'credwrite') { 'credwrite' }
                elseif ($code -eq 401 -or $code -eq 403) { 'auth' }
                elseif ($code -eq 429) { '429' }
                else { 'error' }
    if ($d.status -eq '429') {
      # 연속 429 면 5분 -> 10분 -> 20분 -> 30분(최대)로 늘림. Retry-After 가 더 길면 그걸 따름
      $b = [int]$st.Backoff; $b = if ($b -le 0) { 300 } else { [Math]::Min(1800, $b * 2) }; $st.Backoff = $b
      $st.NextApi = $now.AddSeconds([Math]::Max($b, (RetryAfter $_)))
    }
    elseif ($d.status -eq 'error') { $st.NextApi = $now.AddSeconds([Math]::Max(60, $ApiInterval)) }
  }
}
# remaining time is recomputed on every run, so it ticks even between API calls
$d.five_left = LeftStr $d.five_ts; $d.week_left = LeftStr $d.week_ts; $d.sc_left = LeftStr $d.sc_ts

# ---- 2) today's tokens, incremental ---------------------------------------------------
try {
  $reTs  = [regex]'"timestamp":"([^"]+)"'
  $reId  = [regex]'"id":"(msg_[^"]+)"'
  $reReq = [regex]'"requestId":"([^"]+)"'
  $reI = [regex]'"input_tokens":(\d+)'; $reO = [regex]'"output_tokens":(\d+)'
  $reW = [regex]'"cache_creation_input_tokens":(\d+)'; $reR = [regex]'"cache_read_input_tokens":(\d+)'
  $utf8 = New-Object Text.UTF8Encoding $false
  $proj = Join-Path $cfg 'projects'
  if (Test-Path $proj) {
    $files = Get-ChildItem -LiteralPath $proj -Filter '*.jsonl' -Recurse -File -ErrorAction SilentlyContinue |
             Where-Object { $_.LastWriteTime -ge $today }
    foreach ($f in $files) {
      $pos = [int64]0; if ($st.Files.ContainsKey($f.FullName)) { $pos = [int64]$st.Files[$f.FullName] }
      if ($f.Length -lt $pos) { $pos = 0 }           # file rewritten; dedup set prevents double counting
      if ($f.Length -eq $pos) { continue }
      $fs = $null
      try {
        # FileShare.ReadWrite: Claude Code may be appending to this file right now
        $fs = New-Object IO.FileStream($f.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        [void]$fs.Seek($pos, [IO.SeekOrigin]::Begin)
        $len = [int]($fs.Length - $pos)
        $buf = New-Object byte[] $len
        $got = 0; while ($got -lt $len) { $r2 = $fs.Read($buf, $got, $len - $got); if ($r2 -le 0) { break }; $got += $r2 }
        $last = [Array]::LastIndexOf($buf, [byte]10, $got - 1)   # only consume complete lines
        if ($last -lt 0) { continue }
        $st.Files[$f.FullName] = $pos + $last + 1
        foreach ($line in $utf8.GetString($buf, 0, $last).Split([char]10)) {
          if ($line.IndexOf('"type":"assistant"') -lt 0) { continue }
          $u = $line.LastIndexOf('"usage":{')          # usage comes after content; last match is the real one
          if ($u -lt 0) { continue }
          $mt = $reTs.Matches($line); if ($mt.Count -eq 0) { continue }
          $ts = [DateTimeOffset]::Parse($mt[$mt.Count - 1].Groups[1].Value, $inv).LocalDateTime
          if ($ts -lt $today) { continue }
          $mi = $reId.Match($line); $mr = $reReq.Match($line)
          if ($mi.Success) {                            # same message is logged once per content block
            $key = $mi.Groups[1].Value + '|' + $(if ($mr.Success) { $mr.Groups[1].Value } else { '' })
            if (-not $st.Seen.Add($key)) { continue }
          }
          $us = $line.Substring($u, [Math]::Min(600, $line.Length - $u))
          $m = $reI.Match($us); if ($m.Success) { $st.In  += [int64]$m.Groups[1].Value }
          $m = $reO.Match($us); if ($m.Success) { $st.Out += [int64]$m.Groups[1].Value }
          $m = $reW.Match($us); if ($m.Success) { $st.Cw  += [int64]$m.Groups[1].Value }
          $m = $reR.Match($us); if ($m.Success) { $st.Cr  += [int64]$m.Groups[1].Value }
          $st.N++
        }
      } catch {} finally { if ($fs) { $fs.Dispose() } }
    }
  }
  $d.t_total = Human ($st.In + $st.Out + $st.Cw + $st.Cr)
  $d.t_raw = '{0},{1},{2},{3}' -f $st.In, $st.Out, $st.Cw, $st.Cr
  $d.t_in = Human $st.In; $d.t_out = Human $st.Out; $d.t_cw = Human $st.Cw; $d.t_cr = Human $st.Cr; $d.t_msgs = "$($st.N)"
} catch {}

$d.next_api = if ($st.NextApi -gt [DateTime]::Today.AddYears(-1)) { "$(([DateTimeOffset]$st.NextApi).ToUnixTimeSeconds())" } else { '' }
# ---- 3) write atomically ----------------------------------------------------------------
$d.updated = (Get-Date).ToString('HH:mm:ss', $inv)
WriteAtomic $Out ((($d.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "`n") + "`n")
