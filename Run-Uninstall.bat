@echo off
setlocal
cd /d "%~dp0"
title Happy Study - Uninstall
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0HappyStudy-Uninstall.ps1"
if errorlevel 1 pause