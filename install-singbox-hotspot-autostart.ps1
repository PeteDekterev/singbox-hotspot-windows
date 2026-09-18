# Replaces the legacy Hiddify task with direct sing-box at interactive logon.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$oldTaskName = 'Hiddify VPN + Hotspot'
$taskName = 'sing-box VPN + Hotspot'
$scriptPath = Join-Path $PSScriptRoot 'start-singbox-hotspot.ps1'

Unregister-ScheduledTask -TaskName $oldTaskName -Confirm:$false -ErrorAction SilentlyContinue
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME -RandomDelay (New-TimeSpan -Seconds 15)
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 6) -RestartCount 10 `
    -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
Write-Host "Task '$taskName' was created for direct sing-box startup." -ForegroundColor Green
