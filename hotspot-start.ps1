# Запуск Wi-Fi точки доступа: hosted network (netsh) + ICS (общий доступ к интернету).
# Пример: hotspot-start.ps1 -SSID "MyNet" -Key "password123" -Source "Ethernet"
[CmdletBinding()]
param(
    [string]$SSID = 'DektHotspot',
    [string]$Key = 'dekt12345',
    [string]$Source = '',
    [ValidateSet('WiFi', 'Ethernet')]
    [string]$DeliveryMode = 'WiFi',
    [string]$EthernetAdapter = 'Ethernet 2'
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

function Ensure-Admin {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { return }
    $argsLine = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    foreach ($name in $PSBoundParameters.Keys) {
        $argsLine += " -$name `"$($PSBoundParameters[$name])`""
    }
    Start-Process powershell.exe -ArgumentList $argsLine -Verb RunAs
    exit
}

function Get-RadioSoftwareState {
    $out = netsh wlan show interfaces
    if ($out -match 'Software On') { return 'On' }
    if ($out -match 'Software Off') { return 'Off' }
    return 'Unknown'
}

function Await-WinRtOp($op, [type]$resultType) {
    $m = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
        $_.Name -eq 'AsTask' -and $_.IsGenericMethodDefinition -and
        $_.GetGenericArguments().Count -eq 1 -and
        $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
    } | Select-Object -First 1
    $task = $m.MakeGenericMethod($resultType).Invoke($null, @($op))
    $task.Wait()
    return $task.Result
}

function Await-WinRtAct($op) {
    $m = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
        $_.Name -eq 'AsTask' -and -not $_.IsGenericMethodDefinition -and
        $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncAction'
    } | Select-Object -First 1
    $task = $m.Invoke($null, @($op))
    $task.Wait()
}

function Try-TurnRadioOn {
    try {
        Add-Type -AssemblyName System.Runtime.WindowsRuntime -ErrorAction Stop
        [void][Windows.Devices.Radios.Radio,Windows.System.Devices,ContentType=WindowsRuntime]
        $accOp = [Windows.Devices.Radios.Radio]::RequestAccessAsync()
        $access = Await-WinRtOp $accOp ([Windows.Devices.Radios.RadioAccessStatus])
        if ($access -eq [Windows.Devices.Radios.RadioAccessStatus]::Allowed) {
            $getOp = [Windows.Devices.Radios.Radio]::GetRadiosAsync()
            $radios = Await-WinRtOp $getOp ([System.Collections.Generic.IReadOnlyList[Windows.Devices.Radios.Radio]])
            foreach ($r in $radios) {
                if ($r.Kind -eq [Windows.Devices.Radios.RadioKind]::WiFi -and $r.State -ne [Windows.Devices.Radios.RadioState]::On) {
                    Await-WinRtAct ($r.SetStateAsync([Windows.Devices.Radios.RadioState]::On))
                }
            }
        }
    } catch { }

    try {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class WlanApi {
    [DllImport("wlanapi.dll", SetLastError = true)]
    public static extern uint WlanOpenHandle(uint dwClientVersion, IntPtr pReserved, out uint pdwNegotiatedVersion, out IntPtr phClientHandle);
    [DllImport("wlanapi.dll", SetLastError = true)]
    public static extern uint WlanEnumInterfaces(IntPtr hClientHandle, IntPtr pReserved, out IntPtr ppInterfaceList);
    [DllImport("wlanapi.dll", SetLastError = true)]
    public static extern uint WlanSetInterface(IntPtr hClientHandle, ref Guid pInterfaceGuid, uint OpCode, uint dwDataSize, IntPtr pData, IntPtr pReserved);
    [DllImport("wlanapi.dll", SetLastError = true)]
    public static extern uint WlanCloseHandle(IntPtr hClientHandle, IntPtr pReserved);
}
'@ -ErrorAction Stop
        $client = [IntPtr]::Zero; $ver = 0
        if ([WlanApi]::WlanOpenHandle(2, [IntPtr]::Zero, [ref]$ver, [ref]$client) -eq 0) {
            $list = [IntPtr]::Zero
            if ([WlanApi]::WlanEnumInterfaces($client, [IntPtr]::Zero, [ref]$list) -eq 0) {
                $count = [System.Runtime.InteropServices.Marshal]::ReadInt32($list)
                for ($i = 0; $i -lt $count; $i++) {
                    $infoPtr = [IntPtr]::Add($list, 8 + 532 * $i)
                    $guidBytes = New-Object byte[] 16
                    [System.Runtime.InteropServices.Marshal]::Copy($infoPtr, $guidBytes, 0, 16)
                    $guid = [Guid]::new($guidBytes)
                    $boolPtr = [System.Runtime.InteropServices.Marshal]::AllocHGlobal(4)
                    [System.Runtime.InteropServices.Marshal]::WriteInt32($boolPtr, 1)
                    [void][WlanApi]::WlanSetInterface($client, [ref]$guid, 4, 4, $boolPtr, [IntPtr]::Zero)
                    [System.Runtime.InteropServices.Marshal]::FreeHGlobal($boolPtr)
                }
            }
            [void][WlanApi]::WlanCloseHandle($client, [IntPtr]::Zero)
        }
    } catch { }
}

function Resolve-PublicAdapterName([string]$Preferred) {
    if ($Preferred) {
        if (-not (Get-NetAdapter -Name $Preferred -ErrorAction SilentlyContinue)) { throw "Адаптер '$Preferred' не найден" }
        return $Preferred
    }
    $virtualNames = @(Get-NetAdapter -ErrorAction SilentlyContinue |
        Where-Object { $_.InterfaceDescription -match 'Hosted Network|Miniport|Virtual|TAP|Loopback' } |
        ForEach-Object Name)
    $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
        Sort-Object RouteMetric, InterfaceMetric | Select-Object -First 1
    if ($route -and $virtualNames -notcontains $route.InterfaceAlias) { return $route.InterfaceAlias }
    $internet = @(Get-NetConnectionProfile -ErrorAction SilentlyContinue |
        Where-Object { $_.IPv4Connectivity -eq 'Internet' -and $virtualNames -notcontains $_.InterfaceAlias })
    if ($internet.Count -gt 0) { return $internet[0].InterfaceAlias }
    throw 'Не удалось определить адаптер с доступом в интернет. Укажите вручную: -Source "Ethernet"'
}

function Reset-StaleIcsState {
    # HNetCfg can report no sharing while the legacy HomeNet provider retains a
    # public/private role. HNet_ConnectionProperties is a legacy WMI provider:
    # Set-CimInstance does not persist these values, so use ManagementObject.Put.
    # This is called only after this script has disabled all ICS connections.
    try {
        $scope = New-Object System.Management.ManagementScope('root\Microsoft\HomeNet')
        $scope.Connect()
        $searcher = New-Object System.Management.ManagementObjectSearcher($scope, (New-Object System.Management.ObjectQuery('SELECT * FROM HNet_ConnectionProperties')))
        foreach ($entry in $searcher.Get()) {
            if ([bool]$entry['IsIcsPublic'] -or [bool]$entry['IsIcsPrivate']) {
                $entry['IsIcsPublic'] = $false
                $entry['IsIcsPrivate'] = $false
                $entry.Put() | Out-Null
            }
        }
        $sharedKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\SharedAccess'
        $old = Get-ItemProperty -Path $sharedKey -ErrorAction SilentlyContinue
        if ($old.PrivateIndex -ne 0) { Set-ItemProperty -Path $sharedKey -Name PrivateIndex -Value 0 -ErrorAction Stop }
        if ($old.PublicIndex -ne 0) { Set-ItemProperty -Path $sharedKey -Name PublicIndex -Value 0 -ErrorAction Stop }
        $svc = Get-Service -Name SharedAccess -ErrorAction Stop
        if ($svc.Status -eq 'Running') { Restart-Service -Name SharedAccess -Force -ErrorAction Stop }
        else { Start-Service -Name SharedAccess -ErrorAction Stop }
        Start-Sleep -Seconds 4
    } catch {
        throw "Could not reset stale Internet Connection Sharing state: $($_.Exception.Message)"
    }
}

Ensure-Admin

# Ethernet mode deliberately exits before any Wi-Fi/hosted-network action. ICS
# supports one private interface, so this replaces (rather than accompanies) a
# Wi-Fi hotspot sharing session.
if ($DeliveryMode -eq 'Ethernet') {
    $privateAdapter = Get-NetAdapter -Name $EthernetAdapter -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $privateAdapter) {
        throw "Ethernet adapter '$EthernetAdapter' was not found. Check EthernetAdapter in config\\hotspot-settings.psd1."
    }
    $publicName = Resolve-PublicAdapterName $Source
    if ($publicName -eq $EthernetAdapter) { throw 'The internet source and Ethernet sharing adapter must be different.' }

    $hnet = New-Object -ComObject HNetCfg.HNetShare
    $conns = foreach ($c in $hnet.EnumEveryConnection) {
        $props = $hnet.NetConnectionProps.Invoke($c)
        [pscustomobject]@{
            Name = $props.Name
            Device = $props.DeviceName
            Cfg = $hnet.INetSharingConfigurationForINetConnection.Invoke($c)
        }
    }
    foreach ($c in $conns) { if ($c.Cfg.SharingEnabled) { $c.Cfg.DisableSharing() } }
    Reset-StaleIcsState
    # The SharedAccess restart invalidates COM connection objects; enumerate a
    # fresh collection before assigning the new public/private ICS roles.
    $hnet = New-Object -ComObject HNetCfg.HNetShare
    $conns = foreach ($c in $hnet.EnumEveryConnection) {
        $props = $hnet.NetConnectionProps.Invoke($c)
        [pscustomobject]@{
            Name = $props.Name
            Device = $props.DeviceName
            Cfg = $hnet.INetSharingConfigurationForINetConnection.Invoke($c)
        }
    }

    # ICS must own 192.168.137.1 on the private Ethernet interface. A stopped
    # hosted network can leave that address on its hidden, disconnected adapter,
    # which makes EnableSharing fail with HRESULT 0x80040201.
    $icsConflicts = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -eq '192.168.137.1' -and $_.InterfaceIndex -ne $privateAdapter.ifIndex })
    foreach ($conflict in $icsConflicts) {
        $adapter = Get-NetAdapter -IncludeHidden -InterfaceIndex $conflict.InterfaceIndex -ErrorAction SilentlyContinue
        if ($adapter -and $adapter.Status -eq 'Disconnected') {
            Remove-NetIPAddress -InputObject $conflict -Confirm:$false -ErrorAction Stop
        }
    }
    $icsConflicts = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -eq '192.168.137.1' -and $_.InterfaceIndex -ne $privateAdapter.ifIndex })
    if ($icsConflicts.Count -gt 0) {
        throw '192.168.137.1 is still assigned to another active adapter. Release that address before enabling Ethernet sharing.'
    }

    $pub = @($conns | Where-Object { $_.Name -eq $publicName })[0]
    $priv = @($conns | Where-Object { $_.Name -eq $EthernetAdapter })[0]
    if (-not $pub) { throw "Internet source '$publicName' was not found among Windows network connections." }
    if (-not $priv) { throw "Ethernet adapter '$EthernetAdapter' was not found among Windows network connections." }

    try { $pub.Cfg.EnableSharing(0) }
    catch { throw "Could not set '$publicName' as the Internet source: $($_.Exception.Message)" }
    try { $priv.Cfg.EnableSharing(1) }
    catch { throw "Could not set '$EthernetAdapter' as the sharing interface: $($_.Exception.Message)" }
    # Do not leave an old SSID visible when the selected delivery mode is Ethernet.
    netsh wlan stop hostednetwork | Out-Null
    Write-Host 'Internet sharing is active.' -ForegroundColor Green
    Write-Host ("  Source:      {0}" -f $publicName)
    Write-Host ("  Destination: {0}" -f $EthernetAdapter)
    Write-Host '  ICS assigns 192.168.137.1 and DHCP/DNS automatically; do not set it manually.'
    exit 0
}

Write-Host 'Проверяю состояние Wi-Fi...'
if ((Get-RadioSoftwareState) -ne 'On') {
    Write-Host 'Радио Wi-Fi выключено, пытаюсь включить программно...'
    Try-TurnRadioOn
    Start-Sleep -Seconds 2
    if ((Get-RadioSoftwareState) -ne 'On') {
        Write-Host 'Не удалось включить радио программно.' -ForegroundColor Yellow
        Write-Host 'Включите Wi-Fi вручную (Win+A -> плитка Wi-Fi, или клавиша Fn с иконкой Wi-Fi/самолёта), затем запустите скрипт снова.' -ForegroundColor Yellow
        exit 1
    }
}

Write-Host ("Настраиваю hosted network: SSID=$SSID")
netsh wlan set hostednetwork mode=allow ("ssid=" + $SSID) ("key=" + $Key) keyusage=persistent | Out-Null

$hn = netsh wlan show hostednetwork
if ($hn -notmatch 'Status\s+:\s+Started') {
    $ok = $false
    for ($i = 1; $i -le 3; $i++) {
        netsh wlan start hostednetwork | Out-Null
        Start-Sleep -Seconds 2
        $hn = netsh wlan show hostednetwork
        if ($hn -match 'Status\s+:\s+Started') { $ok = $true; break }
    }
    if (-not $ok) {
        Write-Host 'Не удалось запустить hosted network:' -ForegroundColor Red
        netsh wlan show hostednetwork | Write-Host
        exit 1
    }
}
Write-Host 'Hosted network запущена.'

$hosted = $null
for ($i = 0; $i -lt 20; $i++) {
    $hosted = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceDescription -match 'Hosted Network' } | Select-Object -First 1
    if ($hosted -and $hosted.Status -eq 'Up') { break }
    Start-Sleep -Seconds 1
}
if (-not $hosted) { Write-Host 'Виртуальный адаптер точки доступа не появился.' -ForegroundColor Red; exit 1 }

# ICS всегда использует 192.168.137.1/24 на адаптере точки доступа. Если этот
# адрес закреплён за другим адаптером, ICS внешне включается, но DHCP не работает
# и к SSID нельзя нормально подключиться.
$icsConflicts = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -eq '192.168.137.1' -and $_.InterfaceIndex -ne $hosted.ifIndex })
foreach ($conflict in @($icsConflicts)) {
    $adapter = Get-NetAdapter -InterfaceIndex $conflict.InterfaceIndex -ErrorAction SilentlyContinue
    # A disconnected adapter retaining the former ICS address is stale state.
    # It prevents DHCP on the hosted network after reboot, so remove that exact
    # address automatically. Active adapters are never modified here.
    if ($adapter -and $adapter.Status -eq 'Disconnected') {
        Remove-NetIPAddress -InputObject $conflict -Confirm:$false -ErrorAction Stop
    }
}
$icsConflicts = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -eq '192.168.137.1' -and $_.InterfaceIndex -ne $hosted.ifIndex })
if ($icsConflicts.Count -gt 0) {
    $where = ($icsConflicts | ForEach-Object { "$(($_ | Get-NetAdapter -ErrorAction SilentlyContinue).Name) (ifIndex $($_.InterfaceIndex))" }) -join ', '
    Write-Host "Адрес 192.168.137.1 уже занят: $where" -ForegroundColor Red
    Write-Host 'Удалите этот устаревший адрес или освободите подсеть 192.168.137.0/24, затем запустите скрипт снова.' -ForegroundColor Yellow
    exit 1
}

$publicName = Resolve-PublicAdapterName $Source
Write-Host ("Раздаю интернет с адаптера: $publicName")

$hnet = New-Object -ComObject HNetCfg.HNetShare
$conns = @()
foreach ($c in $hnet.EnumEveryConnection) {
    $props = $hnet.NetConnectionProps.Invoke($c)
    $cfg = $hnet.INetSharingConfigurationForINetConnection.Invoke($c)
    $conns += [pscustomobject]@{ Name = $props.Name; Device = $props.DeviceName; Sharing = $cfg.SharingEnabled; Cfg = $cfg }
}
foreach ($c in $conns) { if ($c.Sharing) { $c.Cfg.DisableSharing() } }

$pub = @($conns | Where-Object { $_.Name -eq $publicName })[0]
$priv = @($conns | Where-Object { $_.Device -match 'Hosted Network' })[0]
if (-not $pub) { Write-Host "Адаптер '$publicName' не найден среди сетевых подключений." -ForegroundColor Red; exit 1 }
if ($pub.Device -match 'Hosted Network') { Write-Host "Адаптер '$publicName' — это сама точка доступа. Укажите источник интернета: -Source \"Ethernet\"" -ForegroundColor Red; exit 1 }
if (-not $priv) { Write-Host 'Не найден виртуальный адаптер hosted network.' -ForegroundColor Red; exit 1 }

try {
    $pub.Cfg.EnableSharing(0)
    $priv.Cfg.EnableSharing(1)
} catch {
    Write-Host ('Ошибка включения ICS: ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host 'Попробуйте указать другой исходный адаптер: -Source "Ethernet"' -ForegroundColor Yellow
    exit 1
}

# ICS должен назначить на private-адаптер 192.168.137.1. Нельзя заменять это
# ручным New-NetIPAddress: адрес появится, но DHCP/DNS от ICS не запустятся.
$ipOk = $false
for ($i = 0; $i -lt 12; $i++) {
    $icsIp = Get-NetIPAddress -InterfaceIndex $hosted.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -eq '192.168.137.1' } | Select-Object -First 1
    if ($icsIp) { $ipOk = $true; break }
    Start-Sleep -Seconds 1
}
if (-not $ipOk) {
    Write-Host 'ICS не назначил 192.168.137.1 (адаптер на APIPA), повторяю настройку...'
    foreach ($c in $conns) { try { $c.Cfg.DisableSharing() } catch { } }
    Start-Sleep -Seconds 2
    $pub.Cfg.EnableSharing(0)
    $priv.Cfg.EnableSharing(1)
    Start-Sleep -Seconds 8
    $icsIp = Get-NetIPAddress -InterfaceIndex $hosted.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -eq '192.168.137.1' } | Select-Object -First 1
    if (-not $icsIp) {
        Write-Host 'ICS не смог назначить 192.168.137.1; сеть остановлена, чтобы не оставлять неработающий SSID.' -ForegroundColor Red
        netsh wlan stop hostednetwork | Out-Null
        exit 1
    }
}

Start-Sleep -Seconds 2
$actualPublic = $null
foreach ($c in $hnet.EnumEveryConnection) {
    $cfg2 = $hnet.INetSharingConfigurationForINetConnection.Invoke($c)
    if ($cfg2.SharingEnabled -and $cfg2.SharingConnectionType -eq 0) {
        $actualPublic = $hnet.NetConnectionProps.Invoke($c).Name
    }
}
$hnText = (netsh wlan show hostednetwork) -join "`n"
$clients = '0'
$m = [regex]::Match($hnText, 'Number of clients\s+:\s+(\d+)')
if ($m.Success) { $clients = $m.Groups[1].Value }

Write-Host ''
Write-Host 'Точка доступа работает.' -ForegroundColor Green
Write-Host ("  SSID:   $SSID")
Write-Host ("  Пароль: $Key")
Write-Host '  IP ПК в точке: 192.168.137.1 (DHCP/DNS раздаются автоматически)'
Write-Host ("  Интернет раздаётся с адаптера: $actualPublic")
Write-Host ("  Подключено клиентов: $clients")
