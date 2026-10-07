@echo off
setlocal
set "LANFU_ROOT=%~dp0"
"%LANFU_ROOT%runtime\node.exe" "%LANFU_ROOT%app\openclaw.mjs" %*
