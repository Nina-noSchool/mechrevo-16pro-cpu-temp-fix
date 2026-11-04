@echo off
title Night Cooling Mode (CPU Boost Off)

:: ==== Step 0: require admin; auto-elevate via UAC if needed ====
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Administrator permission required. A UAC prompt will appear - click Yes.
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo.
echo [1/3] Disable turbo boost  (PERFBOOSTMODE = 0) ...
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFBOOSTMODE 0

echo [2/3] Min processor state = 5%% ...
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 5

echo [3/3] Apply power scheme ...
powercfg /setactive SCHEME_CURRENT

echo.
echo ===== Verify: expected values are 0 and 5 =====
powershell -NoProfile -Command "$s=(Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes').ActivePowerScheme; $b='HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes\'+$s+'\54533251-82be-4824-96c1-47b60b740d00'; $m=(Get-ItemProperty ($b+'\be337238-0d82-4146-a960-4f3749d470c7') -ErrorAction SilentlyContinue).ACSettingIndex; $t=(Get-ItemProperty ($b+'\893dee8e-2bef-41e0-89c6-b55d0929964c') -ErrorAction SilentlyContinue).ACSettingIndex; Write-Output ('  Boost mode          = ' + $m + '   (expect 0 = disabled)'); Write-Output ('  Min processor state = ' + $t + '   (expect 5)')"

echo.
echo Done! CPU is now capped at base clock - cool and quiet.
echo Note: if the Dragon Control Center switches performance modes later, run this again.
pause
