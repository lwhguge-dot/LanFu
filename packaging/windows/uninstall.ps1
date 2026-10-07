$ErrorActionPreference = "SilentlyContinue"
Unregister-ScheduledTask -TaskName "LanFu Gateway" -Confirm:$false
# User data under %USERPROFILE%\.lanfu is intentionally preserved.
