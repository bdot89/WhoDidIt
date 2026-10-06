@echo off
title WhoDidIt - stop starting the sync helper with Windows
rem Removes the shortcut AutoSync-On.cmd added to your Windows Startup folder.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0AutoSync.ps1" -Off
echo.
pause
