@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -File "%~dp0manager-headless.ps1" -NoUi -StartSaved
