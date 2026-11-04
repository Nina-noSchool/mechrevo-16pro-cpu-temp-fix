param(
    [ValidateSet('menu', 'diagnose', 'cool', 'boost', 'monitor')]
    [string]$Action = 'menu',
    [int]$MaxLoops = 0
)

$ErrorActionPreference = 'Stop'

$RegRoot   = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes'
$Subgroup  = '54533251-82be-4824-96c1-47b60b740d00'
$BoostGuid = 'be337238-0d82-4146-a960-4f3749d470c7'   # PERFBOOSTMODE (official GUID per MS Learn)
$MinGuid   = '893dee8e-2bef-41e0-89c6-b55d0929964c'   # PROCTHROTTLEMIN

function Get-SubPath {
    $s = (Get-ItemProperty $RegRoot).ActivePowerScheme
    return "$RegRoot\$s\$Subgroup"
}

function Read-Settings {
    $p = Get-SubPath
    $m = (Get-ItemProperty ($p + '\' + $BoostGuid) -ErrorAction SilentlyContinue).ACSettingIndex
    $t = (Get-ItemProperty ($p + '\' + $MinGuid) -ErrorAction SilentlyContinue).ACSettingIndex
    if ($null -eq $m) { $me = 1; $mt = 'not set (Windows default = enabled)' } else { $me = [int]$m; $mt = "$m" }
    if ($null -eq $t) { $te = 5; $tt = 'not set (Windows default = 5)' } else { $te = [int]$t; $tt = "$t" }
    [pscustomobject]@{ BoostEff = $me; MinEff = $te; BoostText = $mt; MinText = $tt }
}

function Get-LiveSample {
    $ci = Get-CimInstance Win32_PerfFormattedData_Counters_ProcessorInformation | Where-Object { $_.Name -eq '_Total' }
    [pscustomobject]@{ Clock = [int]$ci.PercentofMaximumFrequency; Busy = [int]$ci.PercentProcessorUtility }
}

function Get-AcpiRaw {
    return (Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction SilentlyContinue | Select-Object -First 1).CurrentTemperature
}

function Convert-AcpiRaw([object]$raw) {
    if ($null -eq $raw) { return $null }
    return [math]::Round(($raw / 10) - 273.15, 1)
}

function Test-SensorLatched {
    $r = @(foreach ($i in 1..5) { Get-AcpiRaw; Start-Sleep -Milliseconds 300 })
    if ($null -eq $r[0]) { return 'unavailable' }
    if (@($r | Select-Object -Unique).Count -eq 1) { return 'latched' }
    return 'live'
}

function Get-Verdict($st) {
    if ($st.BoostEff -ge 1 -and $st.MinEff -ge 20) { return 'boost ON + min state cranked - the classic OEM profile problem. Option 2 fixes both.' }
    if ($st.BoostEff -ge 1) { return 'boost ON - AMD rides the thermal ceiling by design. Option 2 caps it for cool/quiet.' }
    if ($st.MinEff -ge 20) { return 'boost off but min state cranked - cores never downclock. Option 2 resets the floor.' }
    return 'power settings already in cool mode.'
}

function Show-Diagnose {
    Write-Output ''
    Write-Output '--- Power settings (AC) ---'
    $st = Read-Settings
    Write-Output ("  Boost mode (AC)          : " + $st.BoostText)
    Write-Output ("  Min processor state (AC) : " + $st.MinText)
    Write-Output '--- Live samples (1s apart) ---'
    foreach ($i in 1..3) {
        $s = Get-LiveSample
        Write-Output ("  sample {0}: clock {1} pct of max freq, cpu busy {2} pct" -f $i, $s.Clock, $s.Busy)
        if ($i -lt 3) { Start-Sleep 1 }
    }
    Write-Output '--- ACPI temperature sensor ---'
    $lk = Test-SensorLatched
    if ($lk -eq 'unavailable') {
        Write-Output '  not available on this system'
    } elseif ($lk -eq 'latched') {
        Write-Output ("  value: " + (Convert-AcpiRaw (Get-AcpiRaw)) + " C  [LATCHED/STALE - do not trust, read the control center overlay]")
    } else {
        Write-Output ("  value: " + (Convert-AcpiRaw (Get-AcpiRaw)) + " C  [live]")
    }
    Write-Output '--- VERDICT ---'
    Write-Output ('  ' + (Get-Verdict (Read-Settings)))
}

function Set-Mode([string]$mode) {
    $boost = 1
    $label = 'BOOST (full speed, boost enabled)'
    if ($mode -eq 'cool') { $boost = 0; $label = 'COOL (base clock cap, quiet)' }
    Write-Output ''
    Write-Output "Applying $label ..."
    powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFBOOSTMODE $boost | Out-Null
    powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 5 | Out-Null
    powercfg /setactive SCHEME_CURRENT | Out-Null
    $st = Read-Settings
    Write-Output ("  Boost mode now          : " + $st.BoostText)
    Write-Output ("  Min processor state now : " + $st.MinText)
    if ($st.BoostEff -eq $boost -and $st.MinEff -eq 5) {
        Write-Output '  OK - applied and verified from registry.'
    } else {
        Write-Output '  WARNING: values did not stick - rerun as Administrator.'
    }
    Write-Output '  Reminder: switching the OEM control center mode may rewrite these - re-apply anytime.'
}

function Show-Monitor {
    Write-Output ''
    Write-Output 'Live monitor - press Ctrl+C to stop.'
    Write-Output ''
    $loop = 0
    while ($true) {
        $loop++
        $s = Get-LiveSample
        $temp = Convert-AcpiRaw (Get-AcpiRaw)
        $tstr = if ($null -eq $temp) { 'n/a' } else { "$temp C" }
        Write-Output ("  clock {0,4} pct | busy {1,3} pct | acpi sensor {2}" -f $s.Clock, $s.Busy, $tstr)
        if ($MaxLoops -gt 0 -and $loop -ge $MaxLoops) { break }
        Start-Sleep 2
    }
}

function Show-About {
    Write-Output ''
    Write-Output 'Jiaolong Thermal Doctor - for Mechrevo Jiaolong 16 Pro (R7 7745HX) and similar laptops.'
    Write-Output ''
    Write-Output 'How to read the diagnosis:'
    Write-Output '  - Boost mode 1/2 with clock samples above 100 pct: AMD boost rides the'
    Write-Output '    thermal ceiling by design (Tjmax 100C, the CPU protects itself).'
    Write-Output '  - Min processor state 20+: the OEM control center cranked it; cores never downclock.'
    Write-Output '  - COOL mode trades up to 30 pct burst performance for ~60-75C and quiet fans.'
    Write-Output '    Switch back to BOOST before gaming.'
    Write-Output '  - ACPI sensor may be latched/stale on many units - trust the control center display.'
    Write-Output '  - The OEM control center rewrites these settings on every mode switch.'
    Write-Output ''
    Write-Output 'https://github.com/Nina-noSchool/mechrevo-16pro-cpu-temp-fix'
}

function Show-Menu {
    while ($true) {
        Write-Output ''
        Write-Output '================================================'
        Write-Output '   Jiaolong Thermal Doctor  v1.1'
        Write-Output '   Mechrevo Jiaolong 16 Pro / R7 7745HX'
        Write-Output '================================================'
        Write-Output '   [1] Diagnose now (read-only)'
        Write-Output '   [2] Switch to COOL mode  (boost off, quiet)'
        Write-Output '   [3] Switch to BOOST mode (full speed, gaming)'
        Write-Output '   [4] Live monitor (Ctrl+C to stop)'
        Write-Output '   [5] About / how to read results'
        Write-Output '   [0] Exit'
        $c = Read-Host 'Select'
        if ([string]::IsNullOrEmpty($c)) { return }
        switch ($c) {
            '1' { Show-Diagnose }
            '2' { Set-Mode 'cool' }
            '3' { Set-Mode 'boost' }
            '4' { Show-Monitor }
            '5' { Show-About }
            '0' { return }
            default { Write-Output '  Unknown option.' }
        }
    }
}

switch ($Action) {
    'diagnose' { Show-Diagnose }
    'cool'     { Set-Mode 'cool' }
    'boost'    { Set-Mode 'boost' }
    'monitor'  { Show-Monitor }
    default    { Show-Menu }
}
