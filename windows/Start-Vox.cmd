@echo off
rem Starts Vox for Windows (minimized console = the server; closing it stops Vox) and opens its window.
cd /d "%~dp0"
start "Vox" /min node src\main.js %*
