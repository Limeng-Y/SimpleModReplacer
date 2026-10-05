@echo off
chcp 65001 >nul
REM ============================================================
REM  Simple Mod Replacer - Launcher
REM  Double-click to run (auto requests administrator rights).
REM  Unattended mode: pass -Yes as first argument
REM    SimpleModReplacer.bat -Yes
REM  Edit paths in SimpleModReplacer.ps1 (User Config section).
REM ============================================================
cd /d "%~dp0"

REM ---- self-elevate (admin) ----
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator privileges...
    if /i "%~1"=="-Yes" (
        powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '-Yes' -Verb RunAs"
    ) else (
        powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    )
    exit /b
)

REM ---- admin now, run main script ----
if /i "%~1"=="-Yes" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0SimpleModReplacer.ps1" -Yes
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0SimpleModReplacer.ps1"
)
