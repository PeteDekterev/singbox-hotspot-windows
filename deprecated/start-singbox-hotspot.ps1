# Start a VLESS/Reality sing-box tunnel from the locally stored profile,
# then enable ICS-hosted Wi-Fi only after the tunnel has Internet connectivity.
[CmdletBinding()]
param(
    [string]$TunnelName = 'tun0',
    [int]$WaitSeconds = 120,
    [int]$Attempts = 2
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSCommandPath
$logPath = Join-Path $root 'vpn-hotspot-startup.log'
$singBox = Join-Path $root 'sing-box-1.14.0\sing-box-1.14.0-windows-amd64\sing-box.exe'
$runtimeDir = Join-Path $env:LOCALAPPDATA 'PortableGit-hotspot'
$runtimeConfig = Join-Path $runtimeDir 'sing-box.json'
$mutex = New-Object System.Threading.Mutex($false, 'Local\PortableGitSingboxHotspot')
$ownsMutex = $false

function Ensure-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { return }
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -TunnelName `"$TunnelName`" -WaitSeconds $WaitSeconds -Attempts $Attempts"
    Start-Process -FilePath powershell.exe -ArgumentList $arguments -Verb RunAs
    exit
}

function Write-StartupLog([string]$Message) {
    $line = '{0:yyyy-MM-dd HH:mm:ss}  {1}' -f (Get-Date), $Message
    Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
}

try {
    Ensure-Admin
    if (-not $mutex.WaitOne(0)) {
        Write-StartupLog 'Another sing-box/hotspot startup instance is already running; this instance exits.'
        exit 0
    }
    $ownsMutex = $true
    Write-StartupLog 'Starting direct sing-box -> hotspot chain.'
    if (-not (Test-Path -LiteralPath $singBox)) { throw "sing-box was not found: $singBox" }
    if (-not (Test-Path -LiteralPath $runtimeConfig)) { throw "The standalone sing-box config was not found: $runtimeConfig" }

    # Prevent stale ICS/DHCP state from a previous run from putting
    # 192.168.137.1 on the wrong adapter.
    & (Join-Path $root 'hotspot-stop.ps1')

    # Direct sing-box must be the only owner of the TUN adapter.
    Get-Process -Name Hiddify,HiddifyCli,'sing-box' -ErrorAction SilentlyContinue | Stop-Process -Force
    $service = Get-Service -Name HiddifyTunnelService -ErrorAction SilentlyContinue
    if ($service -and $service.Status -ne 'Stopped') { Stop-Service -Name HiddifyTunnelService -Force -ErrorAction SilentlyContinue }
    # Wintun teardown is asynchronous. Starting a new core while the previous
    # tun0 instance is still being removed causes "open interface" failures.
    $releaseDeadline = (Get-Date).AddSeconds(30)
    do {
        $oldTunnel = Get-NetAdapter -Name $TunnelName -ErrorAction SilentlyContinue
        if (-not $oldTunnel) { break }
        Start-Sleep -Seconds 1
    } while ((Get-Date) -lt $releaseDeadline)
    if ($oldTunnel) { throw "The previous $TunnelName adapter was not released in time." }

    & $singBox check -c $runtimeConfig | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'sing-box rejected the standalone configuration.' }

    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        Write-StartupLog "Starting direct sing-box attempt $attempt of $Attempts."
        $process = Start-Process -FilePath $singBox -ArgumentList @('run', '-c', $runtimeConfig) -WindowStyle Hidden -PassThru
        $deadline = (Get-Date).AddSeconds($WaitSeconds)
        do {
            $adapter = Get-NetAdapter -Name $TunnelName -ErrorAction SilentlyContinue
            $route = @(Get-NetRoute -InterfaceAlias $TunnelName -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue)
            $profile = Get-NetConnectionProfile -InterfaceAlias $TunnelName -ErrorAction SilentlyContinue
            if ($adapter -and $adapter.Status -eq 'Up' -and $route.Count -gt 0 -and $profile.IPv4Connectivity -eq 'Internet') {
                Write-StartupLog 'Direct sing-box tunnel is ready.'
                & (Join-Path $root 'hotspot-start.ps1') -Source $TunnelName
                if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "hotspot-start.ps1 exited with code $LASTEXITCODE" }
                Write-StartupLog 'Hotspot started successfully through direct sing-box.'
                exit 0
            }
            if ($process.HasExited) {
                Write-StartupLog "sing-box exited during attempt $attempt with code $($process.ExitCode)."
                break
            }
            Start-Sleep -Seconds 3
        } while ((Get-Date) -lt $deadline)

        if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue }
        $releaseDeadline = (Get-Date).AddSeconds(20)
        do {
            $oldTunnel = Get-NetAdapter -Name $TunnelName -ErrorAction SilentlyContinue
            if (-not $oldTunnel) { break }
            Start-Sleep -Seconds 1
        } while ((Get-Date) -lt $releaseDeadline)
        Write-StartupLog "Direct sing-box attempt $attempt did not become ready; retrying if attempts remain."
    }

    throw "Direct sing-box did not become ready after $Attempts attempts of $WaitSeconds seconds. Hotspot was not started."
} catch {
    Write-StartupLog ('ERROR: ' + $_.Exception.Message)
    Write-Error $_
    exit 1
} finally {
    if ($ownsMutex) { $mutex.ReleaseMutex() | Out-Null }
    $mutex.Dispose()
}
