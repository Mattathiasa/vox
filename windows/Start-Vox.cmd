@echo off
rem Starts Vox for Windows (a minimized console runs the server; closing it stops Vox) and opens its window.
cd /d "%~dp0"
set "NODE=%~dp0node\node.exe"
if not exist "%NODE%" set "NODE=node"
start "Vox" /min "%NODE%" src\main.js %*
