@echo off
title Install ClassicAPI (optional extra for WhoDidIt)
rem Downloads ClassicAPI.dll from github.com/brues-code/ClassicAPI, checks it,
rem copies it into your WoW folder and adds it to dlls.txt. Close WoW first.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ClassicApiUpdate.ps1" -Install
echo.
pause
