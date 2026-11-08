# Changelog

本项目的所有显著变更都会记录在这个文件里。
格式参考 [Keep a Changelog](https://keepachangelog.com/)，版本号遵循语义化版本。

## [2.0.0] - 2026-11-08

### Added

- `ThermalCenter.ps1` / `ThermalCenter.bat`：**蛟龙温控中心** —— WPF 图形界面
  - 暗色控制中心风格：四张实时状态卡片（温度 / 时钟 / 占用 / 加速），2 秒自动刷新
  - 一键「低温模式」「满血模式」「深度诊断」，写入后自动回读注册表验证
  - 日志区记录全部操作与判定；异常崩溃自动写 `%TEMP%\thermal-center-crash.log`
  - PowerShell + WPF 实现：零编译、零依赖、约 13KB，规避未签名 exe 的杀软误报问题

## [1.1.0] - 2026-11-05

### Added

- `ThermalDoctor.ps1` / `ThermalDoctor.bat`：一体化控制台——菜单式诊断 / 低温模式 / 满血模式 / 实时监控（时钟、占用、ACPI 温度），支持 `-Action diagnose|cool|boost|monitor` 参数化调用，便于自动化流程与 Agent 集成；每次写入后自动回读注册表验证
- `.github/ISSUE_TEMPLATE/thermal-report.yml`：结构化温度反馈 Issue 表单（强制附 Check_Thermal.bat 输出，用于扩充适用范围数据库）
- README 徽章与 Releases 下载入口

## [1.0.0] - 2026-11-05

首个正式版本。基于 2026-11-04 在蛟龙16 Pro（R7 7745HX + RTX 4070，Windows 11 build 26200）上的完整实测诊断。

### Added

- `Check_Thermal.bat`：只读自查——电源方案、加速模式、最小处理器状态、实时频率/占用采样、温度传感器卡滞检测，并输出自动判定
- `Night_Cooling.bat`：一键低温模式（禁用涡轮加速 + 频率地板 5%），实测 97°C → 74°C、风扇 5037 → 3461 RPM
- `Restore_CPU_Boost.bat`：一键恢复满血加速
- `skills/thermal-selfcheck`：Agent Skill（通用 SKILL.md 格式，ZCode / Claude Code 可装），内置完整诊断流程、四象限判定表与实测避坑清单
- 实测数据与根因解析：控制中心改写最小处理器状态（80%）、AMD 加速贴 Tjmax 行为、ACPI TZ01 锁存假读数
