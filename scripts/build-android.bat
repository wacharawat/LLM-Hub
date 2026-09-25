@echo off
title LLM-Hub Android Auto Build
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build-android.ps1" %*
echo.
pause
