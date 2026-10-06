@echo off
title WhoDidIt - start the sync helper with Windows
rem Adds a shortcut to your Windows Startup folder so WhoDidIt-Sync starts
rem minimised whenever you log in, and starts it now. Undo: AutoSync-Off.cmd
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0AutoSync.ps1"
echo.
pause
