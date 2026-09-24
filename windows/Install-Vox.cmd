@echo off
rem Vox for Windows installer. The release zip includes Node.js and all dependencies,
rem so this just checks things and adds a Start menu shortcut. From a source checkout it runs npm install.
setlocal
cd /d "%~dp0"
echo.
echo  Vox for Windows - setup
echo  -----------------------
set "NODE=%~dp0node\node.exe"
if exist "%NODE%" (
  echo Using the bundled Node.js.
) else (
  where node >nul 2>nul
  if errorlevel 1 (
    echo Node.js 20 or newer is needed. Install it with:
    echo     winget install OpenJS.NodeJS.LTS
    echo then run Install-Vox.cmd again. ^(The release zip from the website includes Node.js.^)
    pause
    exit /b 1
  )
  set "NODE=node"
)
if not exist "public\index.html" if exist "..\web\remote\index.html" xcopy /e /i /y "..\web\remote" "public" >nul
if not exist "node_modules\@lydell\node-pty" (
  echo Installing dependencies...
  call npm install --omit=dev --no-audit --no-fund
  if errorlevel 1 (
    echo npm install failed. See the messages above.
    pause
    exit /b 1
  )
)
"%NODE%" -e "require('@lydell/node-pty')" >nul 2>nul
if errorlevel 1 (
  echo The terminal module didn't load. Please report this at https://github.com/Mattathiasa/vox/issues
  pause
  exit /b 1
)
if exist "D:\" (
  if not exist "D:\Projects" mkdir "D:\Projects"
) else (
  if not exist "%USERPROFILE%\Projects" mkdir "%USERPROFILE%\Projects"
)
echo Creating Start menu and desktop shortcuts "Vox"...
set "VOX_HOME=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$w=New-Object -ComObject WScript.Shell; foreach($dir in @([Environment]::GetFolderPath('Programs'), [Environment]::GetFolderPath('Desktop'))) { $s=$w.CreateShortcut($dir+'\Vox.lnk'); $s.TargetPath=$env:VOX_HOME+'Start-Vox.cmd'; $s.WorkingDirectory=$env:VOX_HOME; $s.WindowStyle=7; $s.Description='Vox voice assistant'; $s.Save() }"
echo.
echo Done. Starting Vox... (next time: Start menu or desktop, "Vox")
echo Your config: %APPDATA%\Vox\config.json  (tools, projects, app shortcuts)
echo Phone from anywhere: install Tailscale, run Remote-Tailscale.cmd, then in Vox: ... - Pair a phone.
call "%~dp0Start-Vox.cmd"
timeout /t 6 >nul
