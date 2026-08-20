@echo off
setlocal
cd /d "%~dp0"
title Happy Study - DWB Serena Tunnel Setup
rem API key is intentionally NOT passed as an argument (it would be visible in
rem the process list). The wizard reads it from .env or HAPPY_STUDY_API_KEY.
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0HappyStudy-SetupWizard.ps1"
if errorlevel 1 pause