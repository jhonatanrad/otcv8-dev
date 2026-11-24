@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -STA -File "%~dp0configure-headless.ps1"
if errorlevel 1 pause
