$ErrorActionPreference = "SilentlyContinue"
# 桌面端登录自启快捷方式（由安装器创建）
$startup = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Startup\LanFu.lnk"
if (Test-Path $startup) { Remove-Item $startup -Force }
# 本地网关的登录自启（新方案，HKCU Run）
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "LanFuGateway"
# 旧方案可能残留的计划任务
Unregister-ScheduledTask -TaskName "LanFu Gateway" -Confirm:$false
# 深链协议
Remove-Item -Path "HKCU:\Software\Classes\lanfu" -Recurse -Force
# 用户数据按设计保留：%USERPROFILE%\.lanfu（助手、记忆、渠道绑定）与 %APPDATA%\LanFu（界面偏好）
