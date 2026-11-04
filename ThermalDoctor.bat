@echo off
title Jiaolong Thermal Doctor
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Administrator permission recommended. A UAC prompt will appear - click Yes.
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ThermalDoctor.ps1"
