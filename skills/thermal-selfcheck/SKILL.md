---
name: thermal-selfcheck
description: Diagnose and fix high CPU temperature at low load on Mechrevo Jiaolong 16 Pro (Ryzen 7 7745HX) and similar Windows laptops. Use when the user reports high CPU temps (90C+) at low utilization, loud fans while idle, thermal throttling worries, or asks about laptop heat problems. Runs a read-only diagnostic, maps findings to known root causes, and can apply reversible power-setting fixes after asking the user.
---

# Thermal Self-Check (Mechrevo Jiaolong 16 Pro / Ryzen 7 7745HX)

Help the user find out why their CPU runs hot and fix the power-settings side of it.
Verified on: Mechrevo Jiaolong 16 Pro, R7 7745HX + RTX 4070 Laptop, Windows 11 build 26200.
The techniques are generic Windows power management and likely apply to other
TongFang-ODM laptops (Mechrevo / Colorful / Machenike etc.) whose control centers
rewrite Windows power settings.

## Background (verified on a real machine)

Symptom: CPU 92-99C while average utilization is only 11-27%, fans loud, control
center shows temps pinned near the ceiling.

Root causes, in combination:

1. The OEM control center (Dragon Performance Control Center) rewrites Windows
   power settings when switching performance modes. On the verified machine its
   Game Mode had set the AC "minimum processor state" to 80%, so cores could
   never downclock below base clock even when idle.
2. AMD's boost algorithm deliberately rides the thermal ceiling: whenever work
   appears it pushes clocks to 4.4-5.1 GHz until it hits ~99C. This is design
   behavior, not a fault. 7745HX Tjmax is 100C and the CPU protects itself, so
   never tell the user the chip is in danger.
3. Many units have a latched/stale ACPI thermal sensor. On the verified machine
   `MSAcpi_ThermalZoneTemperature` (TZ01) returned one constant value for hours
   (98.9C, later 97.2C) that did not track reality. Do not trust it for
   diagnosis; the OEM overlay app reads the real die temp.

## Step 1 - Read-only diagnostic

All reads work without admin. Prefer running the repo's `Check_Thermal.bat`
(`cmd /c Check_Thermal.bat`) when available - it automates everything below.
Otherwise run these PowerShell snippets directly.

Active scheme and effective settings (registry overrides):

```powershell
$s=(Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes').ActivePowerScheme
$b='HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes\'+$s+'\54533251-82be-4824-96c1-47b60b740d00'
$m=(Get-ItemProperty ($b+'\be337238-0d82-4146-a960-4f3749d470c7') -ErrorAction SilentlyContinue).ACSettingIndex
$t=(Get-ItemProperty ($b+'\893dee8e-2bef-41e0-89c6-b55d0929964c') -ErrorAction SilentlyContinue).ACSettingIndex
"boost=$m minState=$t"
```

- `be337238-...` is PERFBOOSTMODE (boost mode): 0=disabled, 1=enabled, 2=aggressive.
  A missing override means Windows default = enabled.
- `893dee8e-...` is PROCTHROTTLEMIN (min processor state): 5 is normal; 20+ means
  the OEM software cranked it.

Live clocks and utilization (locale-independent - do NOT use localized
`Get-Counter` counter paths or `Win32_Processor.CurrentClockSpeed`, both lie):

```powershell
1..3 | ForEach-Object { $ci=Get-CimInstance Win32_PerfFormattedData_Counters_ProcessorInformation | Where-Object { $_.Name -eq '_Total' }; "clock=$($ci.PercentofMaximumFrequency) busy=$($ci.PercentProcessorUtility)"; Start-Sleep 1 }
```

Clock above 100 = boosting above base frequency.

Sensor staleness check (5 reads, 400 ms apart):

```powershell
1..5 | ForEach-Object { (Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature | Select-Object -First 1).CurrentTemperature; Start-Sleep -Milliseconds 400 }
```

Five identical values in a row = latched sensor; ignore its number and tell the
user to read the control center overlay instead.

## Step 2 - Map to a situation

| Boost mode | Min state | Situation | Action |
|---|---|---|---|
| 1 or 2 | 20+ | Classic OEM profile: floor cranked AND boost racing to Tjmax | Fix both (Step 3) |
| 1 or 2 | 5 | Boost racing to thermal ceiling by design | Cap boost if user wants cool/quiet |
| 0 | 20+ | Floor cranked only | Reset floor to 5 |
| 0 | 5 | Power settings are fine | High temp means real load (check Task Manager) or cooling problem (dust / old paste) |

## Step 3 - Fix (always ask the user first)

```powershell
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFBOOSTMODE 0
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 5
powercfg /setactive SCHEME_CURRENT
```

To restore full performance: same commands with `PERFBOOSTMODE 1`.
Companion scripts in the repository root do exactly this:
`Night_Cooling.bat` (cool) and `Restore_CPU_Boost.bat` (full speed).

Verify after applying: re-run the Step 1 registry read; expect `boost=0 minState=5`,
and live samples near 99 pct of max frequency (base clock).

Tell the user the trade-off honestly:
- Burst performance drops up to ~30 percent; sustained all-core work loses little.
- Expect roughly 90C+ -> 60-75C and much quieter fans.
- Settings survive reboots, but the OEM control center will rewrite them again on
  every performance-mode switch - the fix is an undo button, not a vaccine.

## Hard-won gotchas (do not repeat these mistakes)

- PERFBOOSTMODE's official GUID is `be337238-0d82-4146-a960-4f3749d470c7`
  (Microsoft Learn). Many blog guides wrongly cite `ee12f906-d277-404b-b6da-...`,
  which is a different setting entirely.
- `powercfg /q SCHEME_CURRENT SUB_PROCESSOR <setting-guid>` fails on recent
  builds with "setting does not exist". Query the whole subgroup or read the
  registry instead.
- Batch files (.bat) for Chinese-locale Windows must be pure ASCII with CRLF
  line endings. UTF-8 Chinese batch files get shredded by cmd's GBK parsing -
  comments turn into garbage commands. Avoid `%` characters in batch logic;
  use CIM classes instead of localized performance counter paths.
- `powercfg /setacvalueindex` may require elevation; if it fails, rerun from an
  elevated shell. Reads never need elevation.

## Output style

Answer in the user's language. Show the numbers you read, the verdict, then fix
options. Never present the fix as done without re-reading the values afterwards.
