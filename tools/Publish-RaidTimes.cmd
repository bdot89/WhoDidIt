@echo off
title WhoDidIt - publish raid times (maintainer)
rem Refreshes ChronicleData.lua from Chronicle and pushes it to GitHub.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Publish-RaidTimes.ps1" %*
echo.
pause
