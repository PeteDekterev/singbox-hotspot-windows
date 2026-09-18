# Deprecated: starts Hiddify, wait for its VPN tunnel, then launches the Wi-Fi hotspot.
[CmdletBinding()]
param(
    [string]$HiddifyPath = 'C:\Program Files\Hiddify\Hiddify.exe',
    [string]$TunnelName = 'tun0',
    [int]$WaitSeconds = 180
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$logPath = Join-Path $root 'vpn-hotspot-startup.log'

function Write-StartupLog([string]$Message) {
    $line = '{0:yyyy-MM-dd HH:mm:ss}  {1}' -f (Get-Date), $Message
    Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
}

try {
    Write-StartupLog 'Starting Hiddify -> VPN -> hotspot chain.'
    if (-not (Test-Path -LiteralPath $HiddifyPath)) {
        throw "Hiddify was not found: $HiddifyPath"
    }

    if (-not (Get-Process -Name Hiddify -ErrorAction SilentlyContinue)) {
        Start-Process -FilePath $HiddifyPath
        Write-StartupLog 'Hiddify was started.'
    } else {
        Write-StartupLog 'Hiddify is already running.'
    }

    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    do {
        $tun = Get-NetAdapter -Name $TunnelName -ErrorAction SilentlyContinue
        $tunnelDefaultRoute = @(Get-NetRoute -InterfaceAlias $TunnelName -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue)
        $tunnelProfile = Get-NetConnectionProfile -InterfaceAlias $TunnelName -ErrorAction SilentlyContinue
        $tunnelHasInternet = $tunnelProfile -and $tunnelProfile.IPv4Connectivity -eq 'Internet'
        if ($tun -and $tun.Status -eq 'Up' -and $tunnelDefaultRoute.Count -gt 0 -and $tunnelHasInternet) {
            Write-StartupLog "VPN is ready: $TunnelName has an Internet profile and a default route."
            & (Join-Path $root 'hotspot-start.ps1') -Source $TunnelName
            if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "hotspot-start.ps1 exited with code $LASTEXITCODE" }
            Write-StartupLog 'Hotspot started successfully.'
            exit 0
        }
        Start-Sleep -Seconds 3
    } while ((Get-Date) -lt $deadline)

    throw ('VPN did not become ready within {0} seconds: adapter {1} is not the active default route. Hotspot was not started.' -f $WaitSeconds, $TunnelName)
} catch {
    Write-StartupLog ('ERROR: ' + $_.Exception.Message)
    Write-Error $_
    exit 1
}
