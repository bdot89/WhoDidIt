@echo off
title WhoDidIt-Sync (Chronicle kill times)
rem Runs the Chronicle sync helper. Extra arguments are passed through, e.g.
rem   WhoDidIt-Sync.cmd -Once
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0WhoDidIt-Sync.ps1" %*
