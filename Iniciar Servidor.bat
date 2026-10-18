@echo off
title Servidor Unturned
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Iniciar-Servidor.ps1"
if errorlevel 1 pause
