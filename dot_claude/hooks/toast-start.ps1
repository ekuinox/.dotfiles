# Claude Code hook (UserPromptSubmit): ターン開始時刻(UNIX秒)を一時ファイルに記録する
$ErrorActionPreference = 'SilentlyContinue'
try {
  $raw = [Console]::In.ReadToEnd()
  $sid = 'default'
  if ($raw) { try { $o = $raw | ConvertFrom-Json; if ($o.session_id) { $sid = [string]$o.session_id } } catch {} }
  $sid = $sid -replace '[^A-Za-z0-9_-]', '_'
  $f = Join-Path $env:TEMP ("claude-turn-start-" + $sid + ".txt")
  [System.IO.File]::WriteAllText($f, [string][DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
} catch {}

