@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -STA -File "%~dp0manager-headless.ps1"
if errorlevel 1 pause
