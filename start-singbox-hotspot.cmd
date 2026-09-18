@echo off
rem Direct sing-box VPN followed by Wi-Fi hotspot. Hiddify is not started.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-singbox-hotspot.ps1"
echo.
echo See vpn-hotspot-startup.log for the result.
pause
