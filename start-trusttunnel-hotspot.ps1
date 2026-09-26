# Start a TrustTunnel client tunnel from the locally stored profile,
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
$ttClient = Join-Path $root 'trusttunnel-client\trusttunnel_client.exe'
$runtimeDir = Join-Path $env:LOCALAPPDATA 'PortableGit-hotspot'
$runtimeConfig = Join-Path $runtimeDir 'trusttunnel_client.toml'
$ttOutLog = Join-Path $runtimeDir 'trusttunnel-client.out.log'
$ttErrLog = Join-Path $runtimeDir 'trusttunnel-client.err.log'
$mutex = New-Object System.Threading.Mutex($false, 'Local\PortableGitTrusttunnelHotspot')
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

function Write-ClientLogTail {
    foreach ($file in @($ttErrLog, $ttOutLog)) {
        if (Test-Path -LiteralPath $file) {
            $tail = Get-Content -LiteralPath $file -Tail 15 -ErrorAction SilentlyContinue
            foreach ($line in @($tail)) { Write-StartupLog "trusttunnel_client: $line" }
        }
    }
}

try {
    Ensure-Admin
    if (-not $mutex.WaitOne(0)) {
        Write-StartupLog 'Another TrustTunnel/hotspot startup instance is already running; this instance exits.'
        exit 0
    }
    $ownsMutex = $true
    Write-StartupLog 'Starting TrustTunnel -> hotspot chain.'
    if (-not (Test-Path -LiteralPath $ttClient)) { throw "TrustTunnel client was not found: $ttClient" }
    if (-not (Test-Path -LiteralPath $runtimeConfig)) { throw "The TrustTunnel client config was not found: $runtimeConfig" }

    # Prevent stale ICS/DHCP state from a previous run from putting
    # 192.168.137.1 on the wrong adapter.
    & (Join-Path $root 'hotspot-stop.ps1')

    # The TrustTunnel client must be the only owner of the TUN adapter.  The
    # sing-box kill covers the one-time transition away from the dead VLESS server.
    Get-Process -Name Hiddify,HiddifyCli,'sing-box','trusttunnel_client' -ErrorAction SilentlyContinue | Stop-Process -Force
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

    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        Write-StartupLog "Starting TrustTunnel client attempt $attempt of $Attempts."
        Remove-Item -LiteralPath $ttOutLog,$ttErrLog -Force -ErrorAction SilentlyContinue
        $process = Start-Process -FilePath $ttClient -ArgumentList @('-c', "`"$runtimeConfig`"") -WindowStyle Hidden -RedirectStandardOutput $ttOutLog -RedirectStandardError $ttErrLog -PassThru
        $deadline = (Get-Date).AddSeconds($WaitSeconds)
        do {
            $adapter = Get-NetAdapter -Name $TunnelName -ErrorAction SilentlyContinue
            $profile = Get-NetConnectionProfile -InterfaceAlias $TunnelName -ErrorAction SilentlyContinue
            # TrustTunnel covers the default route with many carved CIDR routes instead
            # of a single 0.0.0.0/0 entry, so readiness is judged by the adapter's NCSI state.
            if ($adapter -and $adapter.Status -eq 'Up' -and $profile.IPv4Connectivity -eq 'Internet') {
                Write-StartupLog 'TrustTunnel tunnel is ready.'
                & (Join-Path $root 'hotspot-start.ps1') -Source $TunnelName
                if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "hotspot-start.ps1 exited with code $LASTEXITCODE" }
                Write-StartupLog 'Hotspot started successfully through TrustTunnel.'
                exit 0
            }
            if ($process.HasExited) {
                Write-StartupLog "TrustTunnel client exited during attempt $attempt with code $($process.ExitCode)."
                Write-ClientLogTail
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
        Write-StartupLog "TrustTunnel client attempt $attempt did not become ready; retrying if attempts remain."
    }

    throw "TrustTunnel client did not become ready after $Attempts attempts of $WaitSeconds seconds. Hotspot was not started."
} catch {
    Write-StartupLog ('ERROR: ' + $_.Exception.Message)
    Write-Error $_
    exit 1
} finally {
    if ($ownsMutex) { $mutex.ReleaseMutex() | Out-Null }
    $mutex.Dispose()
}
