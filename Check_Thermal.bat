@echo off
title Thermal Self-Check (read-only)

:: ==== Step 0: require admin; auto-elevate via UAC if needed ====
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Administrator permission required. A UAC prompt will appear - click Yes.
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo.
echo This tool only READS power settings and sensors - it changes nothing.
echo.

echo [1/4] Active power scheme:
powercfg /getactivescheme
echo.

echo [2/4] Power settings and live CPU samples:
powershell -NoProfile -Command "$s=(Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes').ActivePowerScheme; $b='HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes\'+$s+'\54533251-82be-4824-96c1-47b60b740d00'; $m=(Get-ItemProperty ($b+'\be337238-0d82-4146-a960-4f3749d470c7') -ErrorAction SilentlyContinue).ACSettingIndex; $t=(Get-ItemProperty ($b+'\893dee8e-2bef-41e0-89c6-b55d0929964c') -ErrorAction SilentlyContinue).ACSettingIndex; if ($null -eq $m) { $me=1; Write-Output '  Boost mode (AC)          : not set (Windows default = enabled)' } else { $me=[int]$m; Write-Output ('  Boost mode (AC)          : ' + $m) }; if ($null -eq $t) { $te=5; Write-Output '  Min processor state (AC) : not set (Windows default = 5)' } else { $te=[int]$t; Write-Output ('  Min processor state (AC) : ' + $t) }; $mf=0; $mu=0; foreach ($i in 1..3) { $ci=Get-CimInstance Win32_PerfFormattedData_Counters_ProcessorInformation | Where-Object { $_.Name -eq '_Total' }; $f=[int]$ci.PercentofMaximumFrequency; $u=[int]$ci.PercentProcessorUtility; Write-Output ('  Live sample ' + $i + '            : clock ' + $f + ' pct of max freq, cpu busy ' + $u + ' pct'); if ($f -gt $mf) { $mf=$f }; if ($u -gt $mu) { $mu=$u }; Start-Sleep 1 }; if ($me -ge 1 -and $te -ge 20) { Write-Output '  VERDICT: boost ON + min state cranked - the classic OEM profile problem. Run Night_Cooling.bat.' } elseif ($me -ge 1) { Write-Output '  VERDICT: boost ON - AMD rides the thermal ceiling by design. Bursts of 90+ C at low load are normal. Run Night_Cooling.bat for cool mode.' } elseif ($te -ge 20) { Write-Output '  VERDICT: boost off but min state cranked - cores never downclock. Run Night_Cooling.bat.' } else { Write-Output '  VERDICT: power settings already in cool mode.'; if ($mu -ge 50) { Write-Output '  CPU is genuinely busy right now - check Task Manager for the workload.' } else { Write-Output '  If still hot at low load: dust or thermal paste, not power settings.' } }"

echo.
echo [3/4] Temperature sensors:
powershell -NoProfile -Command "$r=@(); foreach ($i in 1..5) { $z=(Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction SilentlyContinue | Select-Object -First 1).CurrentTemperature; $r+=$z; Start-Sleep -Milliseconds 400 }; if ($null -eq $r[0]) { Write-Output '  ACPI thermal zone (CPU)  : not available on this system' } else { $c=[math]::Round(($r[0]/10)-273.15,1); $uniq=($r | Select-Object -Unique).Count; Write-Output ('  ACPI thermal zone (CPU)  : ' + $c + ' C'); if ($uniq -eq 1) { Write-Output '  WARNING: 5 identical readings in a row - sensor looks latched/stale.'; Write-Output '  Trust the control center display for the real CPU temperature.' } }"
where nvidia-smi >nul 2>&1
if %errorlevel% equ 0 (
    echo   GPU temp / util          :
    nvidia-smi --query-gpu=temperature.gpu,utilization.gpu --format=csv,noheader
) else (
    echo   GPU: nvidia-smi not found - skipped
)

echo.
echo [4/4] How to read the results:
echo   - Boost mode 1 or 2 with clock samples above 100 pct:
echo     AMD boost rides the thermal ceiling by design. Night_Cooling.bat caps it.
echo   - Min processor state 20 or higher:
echo     OEM control center cranked it, cores never downclock. Night_Cooling.bat fixes it.
echo   - Boost already 0 and floor 5 but still hot at low load:
echo     Real heavy load, or dust / thermal paste. Clean fans, check Task Manager.
echo   - ACPI sensor warning: ignore that number, trust the control center display.
echo.
pause
