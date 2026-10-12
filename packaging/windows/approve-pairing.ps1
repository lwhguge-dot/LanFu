# 自动批准桌面端的配对请求（安装收尾的一部分）。
#
# 为什么需要这个脚本：桌面外壳以设备签名（Ed25519/v3）身份申请 operator 角色，
# 网关按上游策略要求人工批准这一路径（网页端的令牌直连会被自动批准，但设备签名
# 不会）；而员工没有任何批准入口——批准需要 CLI 或网页管理页。因此安装器替员工
# 批准本机桌面端这一台设备。
param(
  [int]$TimeoutSeconds = 300
)
$ErrorActionPreference = "Continue"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$cli = Join-Path $root "lanfu.cmd"
$cmdExe = Join-Path $env:SystemRoot "System32\cmd.exe"
$logPath = Join-Path $env:TEMP "lanfu-pairing.log"

function Note($text) {
  Add-Content -Path $logPath -Value ((Get-Date -Format "HH:mm:ss") + " " + $text) -ErrorAction SilentlyContinue
}

# CLI 的输出前可能带有非 JSON 的提示行（例如检测到 legacy 目录时的警告），从第一个
# '{' 开始截取；网关未就绪时命令失败，返回 null 由外层重试。
function Invoke-CliJson($arguments) {
  try {
    $out = (& $cmdExe /c ('"' + $cli + '" ' + $arguments)) 2>$null | Out-String
    $idx = $out.IndexOf("{")
    if ($idx -lt 0) { return $null }
    return ($out.Substring($idx) | ConvertFrom-Json)
  } catch { return $null }
}

"=== LanFu 配对批准 $(Get-Date -Format o) ===" | Set-Content -Path $logPath -ErrorAction SilentlyContinue
Note ("CLI: " + $cli)
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
while ((Get-Date) -lt $deadline) {
  $d = Invoke-CliJson "devices list --json"
  if ($d) {
    $paired = @($d.paired | Where-Object { $_.displayName -eq "LanFu" })
    if ($paired.Count -gt 0) { Note "桌面端已在配对列表，无需处理"; exit 0 }
    $pending = @($d.pending)
    if ($pending.Count -gt 0) {
      foreach ($p in $pending) {
        Note ("发现待批准请求 " + $p.requestId + "（" + $p.displayName + "）")
        if ($p.displayName -ne "LanFu") { Note "  非桌面端请求，跳过（不越权批准其它设备）"; continue }
        (& $cmdExe /c ('"' + $cli + '" devices approve ' + $p.requestId)) 2>$null | Out-Null
        Note "  已执行批准"
      }
      Start-Sleep -Seconds 3
      $d2 = Invoke-CliJson "devices list --json"
      if ($d2) {
        $paired2 = @($d2.paired | Where-Object { $_.displayName -eq "LanFu" })
        if ($paired2.Count -gt 0) { Note "桌面端配对完成"; exit 0 }
      }
    }
  }
  Start-Sleep -Seconds 3
}
Note "超时退出。桌面端会持续重连；若仍未配对，可在网页端（http://127.0.0.1:18789）手动批准"
exit 1
