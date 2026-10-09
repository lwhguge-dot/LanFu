$ErrorActionPreference = "SilentlyContinue"

# 先停掉正在运行的进程，否则文件被占用会导致卸载残留。
# 顺序：守护脚本 -> 网关 -> 界面。
# 注意：Get-Process 的返回对象没有 CommandLine 属性（Windows PowerShell 5.1），必须用 CIM 查。
Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
  Where-Object { $_.CommandLine -like "*ensure-gateway*" } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
$node = Join-Path $env:LOCALAPPDATA "Programs\LanFu\runtime\node.exe"
if (Test-Path $node) {
  Get-CimInstance Win32_Process -Filter "Name = 'node.exe'" |
    Where-Object { $_.ExecutablePath -eq $node } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
}
Get-Process -Name LanFu -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Start-Sleep -Seconds 2

# 桌面端登录自启快捷方式（由安装器创建）
$startup = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Startup\LanFu.lnk"
if (Test-Path $startup) { Remove-Item $startup -Force }
# 本地网关的登录自启（HKCU Run）
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "LanFuGateway"
# 旧方案可能残留的计划任务
Unregister-ScheduledTask -TaskName "LanFu Gateway" -Confirm:$false
# 深链协议
Remove-Item -Path "HKCU:\Software\Classes\lanfu" -Recurse -Force
# 员工上下文里启动网关的引导脚本
Remove-Item -Path (Join-Path $env:LOCALAPPDATA "LanFu\start-gateway.cmd") -Force
# 运行日志（不影响用户数据）
Remove-Item -Path (Join-Path $env:TEMP "lanfu-gateway-watchdog.log") -Force
Remove-Item -Path (Join-Path $env:TEMP "lanfu-post-install.log") -Force
# 用户数据按设计保留：%USERPROFILE%\.lanfu（助手、记忆、渠道绑定）与 %APPDATA%\LanFu（界面偏好）
