$ErrorActionPreference = 'SilentlyContinue'
Unregister-ScheduledTask -TaskName 'LanFu Gateway' -Confirm:$false
