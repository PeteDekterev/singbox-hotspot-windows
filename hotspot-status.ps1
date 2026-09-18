# Состояние Wi-Fi точки доступа: радио, hosted network, IP, ICS. Администратор не нужен.
[Console]::OutputEncoding = [Text.Encoding]::UTF8

Write-Host '=== Радио и интерфейс Wi-Fi ===' -ForegroundColor Cyan
netsh wlan show interfaces | Out-Host

Write-Host '=== Hosted network ===' -ForegroundColor Cyan
netsh wlan show hostednetwork | Out-Host

Write-Host '=== Адаптер точки доступа ===' -ForegroundColor Cyan
$hosted = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceDescription -match 'Hosted Network' }
if ($hosted) {
    $hosted | Format-Table Name, Status -AutoSize
    Get-NetIPAddress -InterfaceIndex $hosted.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Format-Table IPAddress, PrefixLength -AutoSize
} else {
    Write-Host 'Виртуальный адаптер не найден (точка не запущена).'
}

Write-Host '=== ICS (общий доступ к подключению) ===' -ForegroundColor Cyan
try {
    $hnet = New-Object -ComObject HNetCfg.HNetShare
    $rows = @()
    foreach ($c in $hnet.EnumEveryConnection) {
        $props = $hnet.NetConnectionProps.Invoke($c)
        $cfg = $hnet.INetSharingConfigurationForINetConnection.Invoke($c)
        if ($cfg.SharingEnabled) {
            $rows += [pscustomobject]@{
                'Подключение' = $props.Name
                'Устройство'  = $props.DeviceName
                'Роль'        = if ($cfg.SharingConnectionType -eq 0) { 'Источник интернета' } else { 'Точка доступа' }
            }
        }
    }
    if ($rows) { $rows | Format-Table -AutoSize } else { Write-Host 'ICS не настроен.' }
} catch {
    Write-Host ('Не удалось прочитать состояние ICS: ' + $_.Exception.Message)
}
