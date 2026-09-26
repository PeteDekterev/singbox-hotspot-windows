@echo off
rem TrustTunnel VPN followed by Wi-Fi hotspot. sing-box and Hiddify are not started.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-trusttunnel-hotspot.ps1"
echo.
echo See vpn-hotspot-startup.log for the result.
pause
