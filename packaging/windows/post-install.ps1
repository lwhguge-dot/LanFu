$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$taskName = 'LanFu Gateway'
$action = New-ScheduledTaskAction -Execute (Join-Path $root 'runtime\node.exe') -Argument ('"' + (Join-Path $root 'app\openclaw.mjs') + '" gateway --port 18789')
$trigger = New-ScheduledTaskTrigger -AtLogOn
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Description 'LanFu Gateway' -Force | Out-Null
