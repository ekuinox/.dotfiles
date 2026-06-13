# Claude Code hook (Stop): ターン経過時間がしきい値以上ならトースト通知を出す
$ErrorActionPreference = 'SilentlyContinue'
$THRESHOLD = 120  # 秒。これ以上かかったターンだけ通知する
try {
  $raw = [Console]::In.ReadToEnd()
  $sid = 'default'
  if ($raw) { try { $o = $raw | ConvertFrom-Json; if ($o.session_id) { $sid = [string]$o.session_id } } catch {} }
  $sid = $sid -replace '[^A-Za-z0-9_-]', '_'
  $f = Join-Path $env:TEMP ("claude-turn-start-" + $sid + ".txt")
  if (Test-Path $f) {
    $startTs = 0
    try { $startTs = [int64]((Get-Content $f -Raw).Trim()) } catch {}
    Remove-Item $f -Force -ErrorAction SilentlyContinue
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $elapsed = $now - $startTs
    if ($startTs -gt 0 -and $elapsed -ge $THRESHOLD) {
      Add-Type -AssemblyName System.Windows.Forms
      Add-Type -AssemblyName System.Drawing
      $n = New-Object System.Windows.Forms.NotifyIcon
      $n.Icon = [System.Drawing.SystemIcons]::Information
      $mins = [math]::Round($elapsed / 60.0, 1)
      $n.BalloonTipTitle = "タスク完了"
      $n.BalloonTipText = "Claude Code: 処理が完了しました (約 " + $mins + " 分 / " + $elapsed + " 秒)"
      $n.Visible = $true
      $n.ShowBalloonTip(10000)
      Start-Sleep -Milliseconds 1800
      $n.Dispose()
    }
  }
} catch {}

