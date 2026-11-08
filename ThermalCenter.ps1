param([switch]$SelfTest)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName WindowsBase

# ---------- validated core logic (same as ThermalDoctor / bats) ----------

$RegRoot   = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes'
$Subgroup  = '54533251-82be-4824-96c1-47b60b740d00'
$BoostGuid = 'be337238-0d82-4146-a960-4f3749d470c7'   # PERFBOOSTMODE
$MinGuid   = '893dee8e-2bef-41e0-89c6-b55d0929964c'   # PROCTHROTTLEMIN

function Get-SubPath {
    $s = (Get-ItemProperty $RegRoot).ActivePowerScheme
    return "$RegRoot\$s\$Subgroup"
}

function Read-Settings {
    $p = Get-SubPath
    $m = (Get-ItemProperty ($p + '\' + $BoostGuid) -ErrorAction SilentlyContinue).ACSettingIndex
    $t = (Get-ItemProperty ($p + '\' + $MinGuid) -ErrorAction SilentlyContinue).ACSettingIndex
    if ($null -eq $m) { $me = 1; $mt = '默认(开)' } else { $me = [int]$m; $mt = "$m" }
    if ($null -eq $t) { $te = 5; $tt = '默认(5)' } else { $te = [int]$t; $tt = "$t" }
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

function Set-PowerMode([string]$mode) {
    $boost = 1
    $label = '满血模式（加速开启）'
    if ($mode -eq 'cool') { $boost = 0; $label = '低温模式（加速关闭）' }
    powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFBOOSTMODE $boost | Out-Null
    powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 5 | Out-Null
    powercfg /setactive SCHEME_CURRENT | Out-Null
    $st = Read-Settings
    if ($st.BoostEff -eq $boost -and $st.MinEff -eq 5) {
        Write-Log ("已切换：{0} —— 加速={1}，最小状态={2}（注册表验证通过）" -f $label, $st.BoostText, $st.MinText)
        Write-Log '提醒：切换控制中心的性能模式可能重写这些设置，随时回来一键恢复。'
    } else {
        Write-Log ("警告：写入未生效（当前 加速={0}，最小状态={1}）—— 请以管理员身份重新运行。" -f $st.BoostText, $st.MinText)
    }
}

function Get-FullDiagnostic {
    $lines = @()
    $st = Read-Settings
    $lines += '--- 电源设置（交流电） ---'
    $lines += ('  加速模式     : ' + $st.BoostText)
    $lines += ('  最小处理器状态: ' + $st.MinText)
    $lines += '--- 实时采样（间隔 1 秒） ---'
    foreach ($i in 1..3) {
        $s = Get-LiveSample
        $lines += ('  采样{0}: 时钟 {1}%，占用 {2}%' -f $i, $s.Clock, $s.Busy)
        if ($i -lt 3) { Start-Sleep 1 }
    }
    $lines += '--- ACPI 温度传感器 ---'
    $lk = Test-SensorLatched
    $tv = Convert-AcpiRaw (Get-AcpiRaw)
    if ($lk -eq 'unavailable') { $lines += '  本机不可用' }
    elseif ($lk -eq 'latched') { $lines += ('  读数: {0}°C  [锁存/失真 —— 请以控制中心显示为准]' -f $tv) }
    else { $lines += ('  读数: {0}°C  [实时]' -f $tv) }
    $lines += '--- 判定 ---'
    if ($st.BoostEff -ge 1 -and $st.MinEff -ge 20) { $lines += '  经典 OEM 配置问题：加速开启 + 频率地板被拉高。点「低温模式」修复。' }
    elseif ($st.BoostEff -ge 1) { $lines += '  加速开启 —— AMD 设计上会贴温度墙跑。想凉快点「低温模式」。' }
    elseif ($st.MinEff -ge 20) { $lines += '  加速已关但地板被拉高，核心无法降频。点「低温模式」修复。' }
    else { $lines += '  电源配置已处于低温模式。' }
    return ($lines -join "`r`n")
}

# ---------- WPF UI ----------

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="蛟龙温控中心 Jiaolong Thermal Center v2.0"
        Width="840" Height="640" WindowStartupLocation="CenterScreen"
        Background="#0B1220" FontFamily="Microsoft YaHei UI">
  <Grid Margin="20">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
    </Grid.RowDefinitions>

    <StackPanel Grid.Row="0" Margin="0,0,0,8">
      <TextBlock Text="蛟龙温控中心" Foreground="#F8FAFC" FontSize="26" FontWeight="Bold"/>
      <TextBlock Text="Jiaolong Thermal Center · 蛟龙16 Pro (R7 7745HX) · 开源温控工具" Foreground="#38BDF8" FontSize="12"/>
    </StackPanel>

    <UniformGrid Grid.Row="1" Columns="4" Margin="0,4,0,4">
      <Border Background="#131C31" BorderBrush="#223047" BorderThickness="1" CornerRadius="10" Margin="4" Padding="12">
        <StackPanel>
          <TextBlock Text="CPU 温度" Foreground="#94A3B8" FontSize="12"/>
          <TextBlock x:Name="CardTemp" Text="-- °C" Foreground="#F87171" FontSize="30" FontWeight="Bold"/>
          <TextBlock Text="ACPI 传感器 · 仅供参考" Foreground="#64748B" FontSize="10"/>
        </StackPanel>
      </Border>
      <Border Background="#131C31" BorderBrush="#223047" BorderThickness="1" CornerRadius="10" Margin="4" Padding="12">
        <StackPanel>
          <TextBlock Text="时钟（基础频率）" Foreground="#94A3B8" FontSize="12"/>
          <TextBlock x:Name="CardClock" Text="-- %" Foreground="#22D3EE" FontSize="30" FontWeight="Bold"/>
          <TextBlock Text="&gt;100% 表示正在加速" Foreground="#64748B" FontSize="10"/>
        </StackPanel>
      </Border>
      <Border Background="#131C31" BorderBrush="#223047" BorderThickness="1" CornerRadius="10" Margin="4" Padding="12">
        <StackPanel>
          <TextBlock Text="CPU 占用" Foreground="#94A3B8" FontSize="12"/>
          <TextBlock x:Name="CardBusy" Text="-- %" Foreground="#A78BFA" FontSize="30" FontWeight="Bold"/>
          <TextBlock Text="整机平均" Foreground="#64748B" FontSize="10"/>
        </StackPanel>
      </Border>
      <Border Background="#131C31" BorderBrush="#223047" BorderThickness="1" CornerRadius="10" Margin="4" Padding="12">
        <StackPanel>
          <TextBlock Text="涡轮加速" Foreground="#94A3B8" FontSize="12"/>
          <TextBlock x:Name="CardBoost" Text="--" Foreground="#34D399" FontSize="30" FontWeight="Bold"/>
          <TextBlock Text="游戏=开 · 挂机=关" Foreground="#64748B" FontSize="10"/>
        </StackPanel>
      </Border>
    </UniformGrid>

    <StackPanel Grid.Row="2" Margin="0,6,0,4">
      <TextBlock x:Name="VerdictLine" Text="状态：加载中…" Foreground="#E2E8F0" FontSize="14" Margin="4,0,4,10"/>
      <StackPanel Orientation="Horizontal">
        <Button x:Name="BtnCool" Content="低温模式" Width="185" Height="50" Margin="4" Background="#064E3B" Foreground="#A7F3D0" BorderBrush="#34D399" FontSize="16" FontWeight="Bold" Cursor="Hand"/>
        <Button x:Name="BtnBoost" Content="满血模式" Width="185" Height="50" Margin="4" Background="#7C2D12" Foreground="#FED7AA" BorderBrush="#FB923C" FontSize="16" FontWeight="Bold" Cursor="Hand"/>
        <Button x:Name="BtnDiag" Content="深度诊断" Width="185" Height="50" Margin="4" Background="#0C2A4A" Foreground="#BAE6FD" BorderBrush="#38BDF8" FontSize="16" FontWeight="Bold" Cursor="Hand"/>
        <Button x:Name="BtnAbout" Content="关于" Width="185" Height="50" Margin="4" Background="#1E293B" Foreground="#CBD5E1" BorderBrush="#475569" FontSize="16" FontWeight="Bold" Cursor="Hand"/>
      </StackPanel>
    </StackPanel>

    <TextBox Grid.Row="3" x:Name="Log" Margin="4,8,4,4" Background="#0F172A" Foreground="#CBD5E1" BorderBrush="#223047" FontFamily="Consolas" FontSize="12" IsReadOnly="True" VerticalScrollBarVisibility="Auto" TextWrapping="Wrap"/>
  </Grid>
</Window>
'@

$window = [Windows.Markup.XamlReader]::Parse($xaml)

$controlNames = @('CardTemp','CardClock','CardBusy','CardBoost','VerdictLine','BtnCool','BtnBoost','BtnDiag','BtnAbout','Log')
foreach ($n in $controlNames) {
    Set-Variable -Name $n -Value $window.FindName($n) -Scope Script
}

if ($SelfTest) {
    $missing = @($controlNames | Where-Object { $null -eq (Get-Variable -Name $_ -Scope Script -ErrorAction SilentlyContinue).Value })
    if ($missing.Count -gt 0) { Write-Output ('SELFTEST FAIL: missing controls: ' + ($missing -join ', ')); exit 1 }
    Write-Output 'SELFTEST OK: XAML parsed, all 10 controls found'
    exit 0
}

# ---------- brushes & log ----------

$BrushOrange = New-Object Windows.Media.SolidColorBrush(([Windows.Media.Color]::FromRgb(0xF5, 0x9E, 0x0B)))
$BrushGreen  = New-Object Windows.Media.SolidColorBrush(([Windows.Media.Color]::FromRgb(0x34, 0xD3, 0x99)))
$BrushRed    = New-Object Windows.Media.SolidColorBrush(([Windows.Media.Color]::FromRgb(0xF8, 0x71, 0x71)))
$BrushText   = New-Object Windows.Media.SolidColorBrush(([Windows.Media.Color]::FromRgb(0xE2, 0xE8, 0xF0)))

function Write-Log([string]$msg) {
    $Log.AppendText("[" + (Get-Date -Format 'HH:mm:ss') + "] " + $msg + "`r`n")
    $Log.ScrollToEnd()
}

function Update-Status {
    $st = Read-Settings
    $s = Get-LiveSample
    $temp = Convert-AcpiRaw (Get-AcpiRaw)
    if ($null -ne $temp) { $CardTemp.Text = "$temp °C" } else { $CardTemp.Text = 'n/a' }
    $CardClock.Text = "$($s.Clock) %"
    $CardBusy.Text = "$($s.Busy) %"
    $boostTxt = switch ($st.BoostEff) { 0 { '关闭' } 1 { '开启' } 2 { '激进' } default { "$($st.BoostEff)" } }
    $CardBoost.Text = $boostTxt
    if ($st.BoostEff -ge 1) { $CardBoost.Foreground = $BrushOrange } else { $CardBoost.Foreground = $BrushGreen }
    if ($st.BoostEff -ge 1 -and $st.MinEff -ge 20) {
        $VerdictLine.Text = "状态：经典 OEM 配置问题 —— 加速开启 + 最小状态 $($st.MinText)% 被拉高。点「低温模式」修复。"
        $VerdictLine.Foreground = $BrushRed
    } elseif ($st.BoostEff -ge 1) {
        $VerdictLine.Text = "状态：满血模式 —— 加速开启，突发时可能 90°C+。挂机/跑测试建议「低温模式」。"
        $VerdictLine.Foreground = $BrushOrange
    } elseif ($st.MinEff -ge 20) {
        $VerdictLine.Text = "状态：加速已关但最小状态 $($st.MinText)% 被拉高，核心无法降频。点「低温模式」修复。"
        $VerdictLine.Foreground = $BrushRed
    } else {
        $VerdictLine.Text = "状态：低温模式 —— 加速关闭，温度友好。打游戏前点「满血模式」。"
        $VerdictLine.Foreground = $BrushGreen
    }
}

# ---------- event handlers ----------

$BtnCool.Add_Click({  Set-PowerMode 'cool';  Update-Status })
$BtnBoost.Add_Click({ Set-PowerMode 'boost'; Update-Status })
$BtnDiag.Add_Click({
    Write-Log '正在深度诊断（约 5 秒）……'
    Write-Log (Get-FullDiagnostic)
    Update-Status
})
$BtnAbout.Add_Click({
    Write-Log '蛟龙温控中心 — 机械革命蛟龙16 Pro (R7 7745HX) 开源温控工具'
    Write-Log '原理与避坑说明见仓库 README：'
    Write-Log 'https://github.com/Nina-noSchool/mechrevo-16pro-cpu-temp-fix'
    Write-Log '温度请以蛟龙控制中心显示为准（本工具的 ACPI 读数可能失真）。'
})

# ---------- startup ----------

Update-Status
Write-Log '欢迎使用蛟龙温控中心。点「低温模式」降温静音，「满血模式」恢复性能，「深度诊断」查看详情。'
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log '提示：当前非管理员运行。设置写入通常仍会生效，如遇失败请用 ThermalCenter.bat（自动提权）重新打开。'
}

try {
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromSeconds(2)
    $timer.Add_Tick({ Update-Status })
    $timer.Start()
    [void]$window.ShowDialog()
    $timer.Stop()
} catch {
    [IO.File]::AppendAllText("$env:TEMP\thermal-center-crash.log", (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $_.Exception.Message + "`r`n" + $_.ScriptStackTrace + "`r`n")
    throw
}
