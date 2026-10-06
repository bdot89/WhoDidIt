@echo off
title WhoDidIt - publish the standard packs (maintainer)
rem After /wdi marks export in game: ships those packs as DefaultPacks.lua.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Publish-Packs.ps1"
echo.
pause
