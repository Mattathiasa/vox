@echo off
rem Publishes Vox's phone remote on your tailnet with HTTPS (voice works on iPhone):
rem   https://<this-pc>.<tailnet>.ts.net  ->  http://127.0.0.1:7788
where tailscale >nul 2>nul
if errorlevel 1 (
  echo Tailscale isn't installed. Get it from https://tailscale.com/download ^(PC and phone^), sign in, then run this again.
  pause
  exit /b 1
)
tailscale serve --bg 7788
tailscale serve status
echo.
echo In the Vox window: menu (...) - Pair a phone, then scan the QR code.
echo To turn it off later: tailscale serve --https=443 off
pause
