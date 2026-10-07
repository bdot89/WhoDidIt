@echo off
title WhoDidIt - keep the sync helper running in the background
rem Adds a scheduled task (your user, no admin) that starts WhoDidIt-Sync with no
rem window when you log in, unlock the PC, and every 15 minutes if it stopped.
rem Starts it now too. Undo: AutoSync-Off.cmd
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0AutoSync.ps1"
echo.
pause
