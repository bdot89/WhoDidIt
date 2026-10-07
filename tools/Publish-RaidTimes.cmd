@echo off
title WhoDidIt - publish the raid times snapshot (maintainer)
rem Puts every guild's raid times from the sync helper into the download (RaidTimes.lua).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Publish-RaidTimes.ps1"
echo.
pause
