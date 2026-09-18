# Deprecated: installs the old Hiddify startup task.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$taskName = 'Hiddify VPN + Hotspot'
$scriptPath = Join-Path $PSScriptRoot 'start-vpn-hotspot.ps1'

$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME -RandomDelay (New-TimeSpan -Seconds 15)
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 5) -RestartCount 10 `
    -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
Write-Host "Deprecated Hiddify task '$taskName' was created." -ForegroundColor Yellow
