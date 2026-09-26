# Replaces the legacy Hiddify and sing-box tasks with TrustTunnel client at interactive logon.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$oldTaskNames = @('Hiddify VPN + Hotspot', 'sing-box VPN + Hotspot')
$taskName = 'TrustTunnel VPN + Hotspot'
$scriptPath = Join-Path $PSScriptRoot 'start-trusttunnel-hotspot.ps1'

foreach ($oldTaskName in $oldTaskNames) {
    Unregister-ScheduledTask -TaskName $oldTaskName -Confirm:$false -ErrorAction SilentlyContinue
}
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME -RandomDelay (New-TimeSpan -Seconds 15)
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 6) -RestartCount 10 `
    -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
Write-Host "Task '$taskName' was created for TrustTunnel client startup." -ForegroundColor Green
