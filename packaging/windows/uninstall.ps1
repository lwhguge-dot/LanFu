$ErrorActionPreference = "SilentlyContinue"
# 免管理员的用户级自启（新方案）
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "LanFuGateway"
# 旧方案可能残留的计划任务
Unregister-ScheduledTask -TaskName "LanFu Gateway" -Confirm:$false
# User data under %USERPROFILE%\.lanfu is intentionally preserved.
