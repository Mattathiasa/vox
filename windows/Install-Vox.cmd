@echo off
rem Vox for Windows installer: checks Node.js, installs dependencies, creates a Start menu shortcut.
setlocal
cd /d "%~dp0"
echo.
echo  Vox for Windows - setup
echo  -----------------------
where node >nul 2>nul
if errorlevel 1 (
  echo Node.js 20 or newer is needed. Install it with:
  echo     winget install OpenJS.NodeJS.LTS
  echo then close this window and run Install-Vox.cmd again.
  pause
  exit /b 1
)
for /f %%v in ('node -p "process.versions.node.split('.')[0]"') do set NODEMAJOR=%%v
if %NODEMAJOR% LSS 20 (
  echo Your Node.js is too old ^(v%NODEMAJOR%^). Run: winget upgrade OpenJS.NodeJS.LTS
  pause
  exit /b 1
)
if not exist "public\index.html" if exist "..\web\remote\index.html" xcopy /e /i /y "..\web\remote" "public" >nul
echo Installing dependencies (terminal support, QR codes)...
call npm install --omit=dev --no-audit --no-fund
if errorlevel 1 (
  echo npm install failed. See the messages above.
  pause
  exit /b 1
)
if not exist "%USERPROFILE%\Projects" mkdir "%USERPROFILE%\Projects"
echo Creating the Start menu shortcut "Vox"...
set "VOX_HOME=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s=(New-Object -ComObject WScript.Shell).CreateShortcut([Environment]::GetFolderPath('Programs')+'\Vox.lnk'); $s.TargetPath=$env:VOX_HOME+'Start-Vox.cmd'; $s.WorkingDirectory=$env:VOX_HOME; $s.WindowStyle=7; $s.Description='Vox voice assistant'; $s.Save()"
echo.
echo Done. Start Vox from the Start menu (search "Vox") or double-click Start-Vox.cmd.
echo Your config: %APPDATA%\Vox\config.json  (tools, projects, app shortcuts)
echo To use your phone from anywhere, install Tailscale and run Remote-Tailscale.cmd.
pause
