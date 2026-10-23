@echo off
rem TrustTunnel VPN followed by the Wi-Fi or Ethernet sharing mode from config\hotspot-settings.psd1.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-trusttunnel-hotspot.ps1"
echo.
echo See vpn-hotspot-startup.log for the result.
pause
