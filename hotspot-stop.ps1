# Остановка Wi-Fi точки доступа: отключает ICS и останавливает hosted network.
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

function Ensure-Admin {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { return }
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Ensure-Admin

$hnet = New-Object -ComObject HNetCfg.HNetShare
foreach ($c in $hnet.EnumEveryConnection) {
    $props = $hnet.NetConnectionProps.Invoke($c)
    $cfg = $hnet.INetSharingConfigurationForINetConnection.Invoke($c)
    if ($cfg.SharingEnabled -and $props.DeviceName -match 'Hosted Network') {
        $cfg.DisableSharing()
        Write-Host ("ICS отключён ({0})" -f $props.Name)
    }
}

netsh wlan stop hostednetwork | Out-Null
Write-Host 'Точка доступа остановлена.' -ForegroundColor Green
