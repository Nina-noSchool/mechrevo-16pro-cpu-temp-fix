# Changelog

本项目的所有显著变更都会记录在这个文件里。
格式参考 [Keep a Changelog](https://keepachangelog.com/)，版本号遵循语义化版本。

## [1.0.0] - 2026-11-05

首个正式版本。基于 2026-11-04 在蛟龙16 Pro（R7 7745HX + RTX 4070，Windows 11 build 26200）上的完整实测诊断。

### Added

- `Check_Thermal.bat`：只读自查——电源方案、加速模式、最小处理器状态、实时频率/占用采样、温度传感器卡滞检测，并输出自动判定
- `Night_Cooling.bat`：一键低温模式（禁用涡轮加速 + 频率地板 5%），实测 97°C → 74°C、风扇 5037 → 3461 RPM
- `Restore_CPU_Boost.bat`：一键恢复满血加速
- `skills/thermal-selfcheck`：Agent Skill（通用 SKILL.md 格式，ZCode / Claude Code 可装），内置完整诊断流程、四象限判定表与实测避坑清单
- 实测数据与根因解析：控制中心改写最小处理器状态（80%）、AMD 加速贴 Tjmax 行为、ACPI TZ01 锁存假读数
