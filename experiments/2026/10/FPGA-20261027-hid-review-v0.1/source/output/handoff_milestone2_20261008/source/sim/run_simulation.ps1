<#
    RTL 仿真门禁。
    [S3-AI | deepseek | 2026-10-14] S3 台与参数负例。
    [S3-REVIEW | Codex | 2026-10-14] 六个负例、原始诊断、ASCII路径及本次指标绑定。

    编译并运行全部测试台，任何一个失败都以退出码 1 结束。烧录脚本在调用
    programmer_cli 之前必须先跑这个脚本，仿真不过就拒绝烧录。

    测试台各管一段：
      tb_tick_rate    量 PT8211 的采样节拍周期，只有 576 个 27 MHz 时钟才算对
      tb_song_timing  量一遍曲子实际占多少采样节拍、发了多少个音符事件
      tb_poly         量顶层连线：复位、默认速度档位、两个按键
      tb_adsr         覆盖各阶段松键、释放归零与快速重按
      tb_voice_retrigger  覆盖同音重按、满声部窃取与释放声部复用
      tb_voice_order  覆盖长时间演奏后的最老声部判断
      tb_event_fifo   覆盖空满保护、满队列同拍读写和顺序
      tb_song_backpressure 覆盖播放器保持未被接收的事件
      tb_mode_uart   覆盖串口到顶层模式/事件路径；强制加速采样，非真实音频捕获
      tb_gpio_keyboard  [S2] 12 路 GPIO 键的同步/消抖/边沿/背压/flush 与响应上界
      tb_gpio_top       [S2] 顶层模式回归：GPIO 退出演示、四键同拍、Panic 优先
      tb_audio_capture 从真实 PT8211 引脚解码样本；PCM/FFT 另由 tools/run_audio_verification.ps1 验收
      tb_i2s_tx        [S3] 标准 I2S 发送器：12.288 MHz/48 kHz 与 27 MHz/46.875 kHz
                       两个档案各 16/24 位共四组合的周期、一位延迟、逐位解码、
                       抗撕裂、复位恢复、数字静音、负面控制与无 X
      tb_i2s_tx_params [S3] 参数负例：五组非法配置必须被 S3_PARAM_INVALID 拦截
      tb_mcp3208_spi   [S4] MCP3208 19 拍 DS21298E 帧、双通道、固定种子随机值与帧内复位
      tb_mcp3208_i2s_coexist [S4] ADC 事务期间 PT8211 节拍仍严格 576 拍
      tb_mcp3208_params [S4] 27 MHz/250 kHz 生产参数、分频钳位与 SPI_HZ=0 守护
      tb_pressure_bend [S5] 640 个压力 tick 与 4096 个弯音 ADC 码逐值对照参考
      tb_s6_audio      [S6] 3584 相位点、1024+256 混合点、510 混音样本与 32 个 FIR 样本
      tb_s6_rom_prim   [S6] 行为版与显式 Gowin pROM 版波表逐值等价（512 地址 × 5 小数位 × 3 混合）
      tb_shared_engine [S6] 共享引擎原型：分量和与逐声部参考逐位相等，全局交叉混合偏差 ≤2 LSB
      tb_top_i2s       [集成] 标准 I2S 档顶层（AUDIO_IF=1）：48 kHz/3.072 MHz/64 BCK、
                       24 位槽与 final_sample 逐帧对照、相位增量对 48 kHz 理想值、数字静音
#>
param(
    [string]$Iverilog = '',
    [string]$Vvp = '',
    [string]$AudioCaptureDir = '',
    [string]$MetricsDir = '',
    [string]$BuildDir = '',
    [switch]$SkipAudioCapture
)

$ErrorActionPreference = 'Stop'
$sourceRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Find-Tool {
    param([string]$Name, [string]$FromEnv, [string[]]$Candidates)
    if ($FromEnv) { return $FromEnv }
    foreach ($c in $Candidates) {
        if (Test-Path -LiteralPath $c -PathType Leaf) { return $c }
    }
    $found = Get-Command $Name -ErrorAction SilentlyContinue
    if ($found) { return $found.Source }
    return ''
}

$iverilogCandidates = @('C:\iverilog\bin\iverilog.exe', (Join-Path $PSScriptRoot '..\..\..\..\..\msys64\ucrt64\bin\iverilog.exe'))
$vvpCandidates = @('C:\iverilog\bin\vvp.exe', (Join-Path $PSScriptRoot '..\..\..\..\..\msys64\ucrt64\bin\vvp.exe'))
foreach ($pf in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
    if ($pf) {
        $iverilogCandidates += (Join-Path $pf 'iverilog\bin\iverilog.exe')
        $vvpCandidates += (Join-Path $pf 'iverilog\bin\vvp.exe')
    }
}

if (-not $Iverilog) { $Iverilog = Find-Tool -Name 'iverilog' -FromEnv $env:IVERILOG -Candidates $iverilogCandidates }
if (-not $Vvp)      { $Vvp      = Find-Tool -Name 'vvp'      -FromEnv $env:VVP      -Candidates $vvpCandidates }
# MSYS2 Icarus needs its UCRT64 DLL directory on PATH.
if ($Iverilog -and $Vvp) {
    $toolDir = Split-Path -Parent $Iverilog
    if ($env:PATH -notlike "*$toolDir*") { $env:PATH = "$toolDir;$env:PATH" }
}

if (-not $Iverilog -or -not (Test-Path -LiteralPath $Iverilog -PathType Leaf)) {
    Write-Error "找不到 iverilog。安装 Icarus Verilog，或用 -Iverilog 指定路径。仿真门禁无法跳过。"
    exit 1
}
if (-not $Vvp -or -not (Test-Path -LiteralPath $Vvp -PathType Leaf)) {
    Write-Error "找不到 vvp。安装 Icarus Verilog，或用 -Vvp 指定路径。仿真门禁无法跳过。"
    exit 1
}

Push-Location $sourceRoot
try {
    # S1 捕获数据默认放在工作区 tmp，不向源码目录写大文件。
    if (-not $AudioCaptureDir) {
        $repoRoot = (Resolve-Path -LiteralPath (Join-Path $sourceRoot '..\..\..')).Path
        $AudioCaptureDir = Join-Path $repoRoot 'tmp\audio_capture'
    }
    New-Item -ItemType Directory -Force -Path $AudioCaptureDir | Out-Null
    $AudioCaptureDir = (Resolve-Path -LiteralPath $AudioCaptureDir).Path
    if (-not $BuildDir) {
        $repoRoot = (Resolve-Path -LiteralPath (Join-Path $sourceRoot '..\..\..')).Path
        $BuildDir = Join-Path $repoRoot 'tmp\simulation_build'
    }
    New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
    $BuildDir = (Resolve-Path -LiteralPath $BuildDir).Path
    # S3 指标文件同样写到工作区 tmp，不向源码目录写大文件。
    if (-not $MetricsDir) {
        $repoRoot = (Resolve-Path -LiteralPath (Join-Path $sourceRoot '..\..\..')).Path
        $MetricsDir = Join-Path $repoRoot 'tmp\i2s_metrics'
    }
    New-Item -ItemType Directory -Force -Path $MetricsDir | Out-Null
    $MetricsDir = (Resolve-Path -LiteralPath $MetricsDir).Path
    foreach ($runtimeDir in @($AudioCaptureDir, $BuildDir, $MetricsDir)) {
        if ($runtimeDir -match '[^\x00-\x7F]') {
            throw "Icarus runtime path must use ASCII characters (vvp plusargs encoding): $runtimeDir"
        }
    }
    $suite = @(
        @{ Name = 'tb_tick_rate';   Top = 'sim\tb_tick_rate.v';   Src = @('rtl\audio\pt8211_tx.v') },
        @{ Name = 'tb_song_timing'; Top = 'sim\tb_song_timing.v'; Src = @('rtl\audio\song_player.v') },
        @{ Name = 'tb_adsr';        Top = 'sim\tb_adsr.v';        Src = @('rtl\audio\adsr.v') },
        @{ Name = 'tb_voice_retrigger'; Top = 'sim\tb_voice_retrigger.v'; Src = @(
                'rtl\audio\voice_alloc.v', 'rtl\audio\poly_voice.v',
                'rtl\audio\adsr.v', 'rtl\audio\dds_osc.v', 'rtl\audio\note_phase_inc.v') },
        @{ Name = 'tb_voice_order'; Top = 'sim\tb_voice_order.v'; Src = @('rtl\audio\voice_alloc.v') },
        @{ Name = 'tb_event_fifo'; Top = 'sim\tb_event_fifo.v'; Src = @('rtl\audio\event_fifo.v') },
        @{ Name = 'tb_song_backpressure'; Top = 'sim\tb_song_backpressure.v'; Src = @('rtl\audio\song_player.v') },
        @{ Name = 'tb_gpio_keyboard'; Top = 'sim\tb_gpio_keyboard.v'; Src = @('rtl\audio\gpio_keyboard.v') },
        @{ Name = 'tb_mode_uart'; Top = 'sim\tb_mode_uart.v'; Src = @(
                'rtl\top.v',
                'rtl\audio\dds_osc.v', 'rtl\audio\adsr.v', 'rtl\audio\poly_voice.v',
                'rtl\audio\poly_voice_s6.v', 'rtl\audio\note_phase_inc.v',
                'rtl\audio\wavetable_osc_dual_s6.v',
                'rtl\audio\event_fifo.v', 'rtl\audio\voice_alloc.v',
                'rtl\audio\song_player.v', 'rtl\audio\mixer_s6.v',
                'rtl\audio\pt8211_tx.v', 'rtl\audio\uart_ctrl.v',
                'rtl\audio\gpio_keyboard.v', 'rtl\audio\mcp3208_spi.v',
                'rtl\audio\pressure_bend.v', 'rtl\audio\shared_wavetable_engine.v',
                'rtl\audio\gowin_prom_guitar_bank.v',
                'rtl\audio\global_crossfade.v', 'rtl\audio\gowin_prom_wave_sine.v',
                'rtl\audio\gowin_prom_wave_bright.v', 'sim\gowin_prom_model.v',
                'sim\mcp3208_model.v') },
        @{ Name = 'tb_gpio_top'; Top = 'sim\tb_gpio_top.v'; Src = @(
                'rtl\top.v',
                'rtl\audio\dds_osc.v', 'rtl\audio\adsr.v', 'rtl\audio\poly_voice.v',
                'rtl\audio\poly_voice_s6.v', 'rtl\audio\note_phase_inc.v',
                'rtl\audio\wavetable_osc_dual_s6.v',
                'rtl\audio\event_fifo.v', 'rtl\audio\voice_alloc.v',
                'rtl\audio\song_player.v', 'rtl\audio\mixer_s6.v',
                'rtl\audio\pt8211_tx.v', 'rtl\audio\uart_ctrl.v',
                'rtl\audio\gpio_keyboard.v', 'rtl\audio\mcp3208_spi.v',
                'rtl\audio\pressure_bend.v', 'rtl\audio\shared_wavetable_engine.v',
                'rtl\audio\gowin_prom_guitar_bank.v',
                'rtl\audio\global_crossfade.v', 'rtl\audio\gowin_prom_wave_sine.v',
                'rtl\audio\gowin_prom_wave_bright.v', 'sim\gowin_prom_model.v',
                'sim\mcp3208_model.v') },
        @{ Name = 'tb_poly'; Top = 'sim\tb_poly.v'; Src = @(
                'rtl\top.v',
                'rtl\audio\dds_osc.v', 'rtl\audio\adsr.v', 'rtl\audio\poly_voice.v',
                'rtl\audio\poly_voice_s6.v', 'rtl\audio\note_phase_inc.v',
                'rtl\audio\wavetable_osc_dual_s6.v',
                'rtl\audio\event_fifo.v', 'rtl\audio\voice_alloc.v',
                'rtl\audio\song_player.v', 'rtl\audio\mixer_s6.v',
                'rtl\audio\pt8211_tx.v', 'rtl\audio\uart_ctrl.v',
                'rtl\audio\gpio_keyboard.v', 'rtl\audio\mcp3208_spi.v',
                'rtl\audio\pressure_bend.v', 'rtl\audio\shared_wavetable_engine.v',
                'rtl\audio\gowin_prom_guitar_bank.v',
                'rtl\audio\global_crossfade.v', 'rtl\audio\gowin_prom_wave_sine.v',
                'rtl\audio\gowin_prom_wave_bright.v', 'sim\gowin_prom_model.v',
                'sim\mcp3208_model.v') },
        @{ Name = 'tb_audio_capture'; Top = 'sim\tb_audio_capture.v'; Src = @(
                'rtl\top.v',
                'rtl\audio\dds_osc.v', 'rtl\audio\adsr.v', 'rtl\audio\poly_voice.v',
                'rtl\audio\poly_voice_s6.v', 'rtl\audio\note_phase_inc.v',
                'rtl\audio\wavetable_osc_dual_s6.v',
                'rtl\audio\event_fifo.v', 'rtl\audio\voice_alloc.v',
                'rtl\audio\song_player.v', 'rtl\audio\mixer_s6.v',
                'rtl\audio\pt8211_tx.v', 'rtl\audio\uart_ctrl.v',
                'rtl\audio\gpio_keyboard.v', 'rtl\audio\mcp3208_spi.v',
                'rtl\audio\pressure_bend.v', 'rtl\audio\shared_wavetable_engine.v',
                'rtl\audio\gowin_prom_guitar_bank.v',
                'rtl\audio\global_crossfade.v', 'rtl\audio\gowin_prom_wave_sine.v',
                'rtl\audio\gowin_prom_wave_bright.v', 'sim\gowin_prom_model.v',
                'sim\mcp3208_model.v') },
        @{ Name = 'tb_i2s_tx'; Top = 'sim\tb_i2s_tx.v'; Src = @(
                'rtl\audio\i2s_tx.v', 'sim\i2s_rx_model.v', 'sim\i2s_tx_checker.v') },
        @{ Name = 'tb_mcp3208_spi'; Top = 'sim\tb_mcp3208_spi.v'; Src = @(
                'rtl\audio\mcp3208_spi.v', 'sim\mcp3208_model.v') },
        @{ Name = 'tb_mcp3208_i2s_coexist'; Top = 'sim\tb_mcp3208_i2s_coexist.v'; Src = @(
                'rtl\audio\mcp3208_spi.v', 'rtl\audio\pt8211_tx.v',
                'sim\mcp3208_model.v') },
        @{ Name = 'tb_mcp3208_params'; Top = 'sim\tb_mcp3208_params.v'; Src = @(
                'rtl\audio\mcp3208_spi.v', 'sim\mcp3208_model.v') },
        @{ Name = 'tb_pressure_bend'; Top = 'sim\tb_pressure_bend.v'; Src = @(
                'rtl\audio\pressure_bend.v', 'rtl\audio\adsr.v') },
        @{ Name = 'tb_s6_audio'; Top = 'sim\tb_s6_audio.v'; Src = @(
                'rtl\audio\wavetable_rom_dual.v', 'rtl\audio\wavetable_osc_dual_s6.v',
                'rtl\audio\mixer_s6.v') },
        @{ Name = 'tb_top_s4s6'; Top = 'sim\tb_top_s4s6.v'; Src = @(
                'rtl\top.v',
                'rtl\audio\dds_osc.v', 'rtl\audio\adsr.v', 'rtl\audio\poly_voice.v',
                'rtl\audio\poly_voice_s6.v', 'rtl\audio\note_phase_inc.v',
                'rtl\audio\wavetable_osc_dual_s6.v',
                'rtl\audio\event_fifo.v', 'rtl\audio\voice_alloc.v',
                'rtl\audio\song_player.v', 'rtl\audio\mixer_s6.v',
                'rtl\audio\pt8211_tx.v', 'rtl\audio\uart_ctrl.v',
                'rtl\audio\gpio_keyboard.v', 'rtl\audio\mcp3208_spi.v',
                'rtl\audio\pressure_bend.v', 'rtl\audio\shared_wavetable_engine.v',
                'rtl\audio\gowin_prom_guitar_bank.v',
                'rtl\audio\global_crossfade.v', 'rtl\audio\gowin_prom_wave_sine.v',
                'rtl\audio\gowin_prom_wave_bright.v', 'sim\gowin_prom_model.v',
                'sim\mcp3208_model.v') },
        @{ Name = 'tb_top_i2s'; Top = 'sim\tb_top_i2s.v'; Src = @(
                'rtl\top.v',
                'rtl\audio\dds_osc.v', 'rtl\audio\adsr.v', 'rtl\audio\poly_voice.v',
                'rtl\audio\poly_voice_s6.v', 'rtl\audio\wavetable_osc_dual_s6.v',
                'rtl\audio\note_phase_inc.v',
                'rtl\audio\event_fifo.v', 'rtl\audio\voice_alloc.v',
                'rtl\audio\song_player.v', 'rtl\audio\mixer_s6.v',
                'rtl\audio\pt8211_tx.v', 'rtl\audio\uart_ctrl.v',
                'rtl\audio\gpio_keyboard.v', 'rtl\audio\mcp3208_spi.v',
                'rtl\audio\pressure_bend.v', 'rtl\audio\shared_wavetable_engine.v',
                'rtl\audio\gowin_prom_guitar_bank.v',
                'rtl\audio\global_crossfade.v', 'rtl\audio\i2s_tx.v',
                'rtl\audio\gowin_prom_wave_sine.v', 'rtl\audio\gowin_prom_wave_bright.v',
                'sim\gowin_prom_model.v', 'sim\mcp3208_model.v') },
        @{ Name = 'tb_s6_rom_prim'; Top = 'sim\tb_s6_rom_prim.v'; Src = @(
                'rtl\audio\wavetable_osc_dual_s6.v', 'rtl\audio\wavetable_osc_dual_prom.v',
                'rtl\audio\gowin_prom_wave_sine.v', 'rtl\audio\gowin_prom_wave_bright.v',
                'sim\gowin_prom_model.v') },
        @{ Name = 'tb_piano_bank'; Top = 'sim\tb_piano_bank.v'; Src = @(
                'rtl\audio\gowin_prom_piano_bank.v', 'sim\gowin_prom_model.v') },
        @{ Name = 'tb_key_gain'; Top = 'sim\tb_key_gain.v'; Src = @(
                'rtl\audio\shared_wavetable_engine.v',
                'rtl\audio\gowin_prom_guitar_bank.v',
                'rtl\audio\gowin_prom_wave_sine.v', 'rtl\audio\gowin_prom_wave_bright.v',
                'sim\gowin_prom_model.v') },
        # 力度定义为 0..127；128..255 在入口饱和。旧实现 128*256 截成 0（静音）。
        @{ Name = 'tb_velocity_bounds'; Top = 'sim\tb_velocity_bounds.v'; Src = @(
                'rtl\audio\shared_wavetable_engine.v',
                'rtl\audio\gowin_prom_wave_sine.v', 'rtl\audio\gowin_prom_wave_bright.v',
                'sim\gowin_prom_model.v') },
        @{ Name = 'tb_piano_engine'; Top = 'sim\tb_piano_engine.v'; Src = @(
                'rtl\audio\shared_wavetable_engine.v',
                'rtl\audio\gowin_prom_guitar_bank.v',
                'rtl\audio\gowin_prom_wave_sine.v', 'rtl\audio\gowin_prom_piano_bank.v',
                'sim\gowin_prom_model.v') },
        @{ Name = 'tb_piano_morph'; Top = 'sim\tb_piano_morph.v'; Src = @(
                'rtl\audio\shared_wavetable_engine.v',
                'rtl\audio\gowin_prom_guitar_bank.v',
                'rtl\audio\gowin_prom_wave_sine.v', 'rtl\audio\gowin_prom_piano_bank.v',
                'sim\gowin_prom_model.v') },
        @{ Name = 'tb_piano_envelope'; Top = 'sim\tb_piano_envelope.v'; Src = @(
                'rtl\audio\voice_transition.v', 'rtl\audio\adsr.v') },
        @{ Name = 'tb_shared_engine'; Top = 'sim\tb_shared_engine.v'; Src = @(
                'rtl\audio\shared_wavetable_engine.v',
                'rtl\audio\gowin_prom_guitar_bank.v', 'rtl\audio\global_crossfade.v',
                'rtl\audio\wavetable_osc_dual_s6.v', 'rtl\audio\gowin_prom_wave_sine.v',
                'rtl\audio\gowin_prom_wave_bright.v', 'rtl\audio\gowin_prom_piano_bank.v',
                'sim\gowin_prom_model.v') }
    )

    # FSR gain is part of the product; these self-checking benches are also run
    # when the full programming gate is used in a later hardware session.
    $suite += @(
        @{ Name = 'tb_pressure_gain'; Top = 'sim\tb_pressure_gain.v'; Src = @(
                'rtl\audio\global_crossfade.v') },
        @{ Name = 'tb_pressure_top'; Top = 'sim\tb_pressure_top.v'; Src = @(
                'rtl\top.v', 'rtl\audio\adsr.v', 'rtl\audio\note_phase_inc.v',
                'rtl\audio\event_fifo.v', 'rtl\audio\voice_alloc.v',
                'rtl\audio\song_player.v', 'rtl\audio\pt8211_tx.v',
                'rtl\audio\uart_ctrl.v', 'rtl\audio\gpio_keyboard.v',
                'rtl\audio\mcp3208_spi.v', 'rtl\audio\pressure_bend.v',
                'rtl\audio\shared_wavetable_engine.v',
                'rtl\audio\gowin_prom_guitar_bank.v', 'rtl\audio\global_crossfade.v',
                'rtl\audio\i2s_tx.v', 'rtl\audio\gowin_prom_wave_sine.v',
                'rtl\audio\gowin_prom_wave_bright.v', 'sim\gowin_prom_model.v',
                'sim\mcp3208_model.v', 'sim\i2s_rx_model.v') }
    )

    # Shared board controls are required by every bench containing rtl/top.v.
    foreach ($entry in $suite) {
        if ($entry.Src -contains 'rtl\top.v') { $entry.Src += @('rtl\audio\instrument_controls.v','rtl\audio\voice_transition.v','rtl\audio\note_ownership.v','rtl\audio\gowin_prom_bright_bank.v','rtl\audio\gowin_prom_piano_bank.v','rtl\audio\bend_ratio_pipeline.v','rtl\video\ui_status_export.v','rtl\video\ui_audio_visual_export.v') }
    }
    $audioSources = @(Get-ChildItem -LiteralPath 'rtl/audio' -Filter '*.v' | ForEach-Object FullName) + @('rtl\video\ui_status_export.v','rtl\video\ui_audio_visual_export.v')
    foreach ($name in @('tb_timbre_controls','tb_timbre_audio','tb_timbre_uart','tb_timbre_top','tb_uart_dashboard')) {
        $suite += @{ Name=$name; Top=('sim\'+$name+'.v'); Src=($audioSources + @('rtl\top.v','sim\gowin_prom_model.v','sim\mcp3208_model.v','sim\i2s_rx_model.v')) }
    }

    foreach ($name in @('tb_architecture_equivalence','tb_shared_bend_equivalence','tb_bend_equivalence','tb_shared_master','tb_frame_velocity')) {
        $suite += @{ Name=$name; Top=('sim\'+$name+'.v'); Src=($audioSources + @('sim\gowin_prom_model.v','sim\reference\baseline_shared_wavetable_engine.v','sim\reference\baseline_pressure_bend.v')) }
    }
    foreach ($name in @('tb_headroom','tb_bend_precision','tb_adc_reset_top','tb_control_sampling','tb_mute_slew','tb_voice_transition','tb_voice_transition_audio','tb_voice_transition_top','tb_note_ownership','tb_note_ownership_top','tb_bright_banks','tb_bandlimit_engine','tb_wide_master','tb_precision_audio')) {
        $suite += @{ Name=$name; Top=('sim\'+$name+'.v'); Src=($audioSources + @('rtl\top.v','sim\gowin_prom_model.v','sim\mcp3208_model.v')) }
    }

    $suite += @{ Name='tb_bandlimit_engine_wide'; Top='sim\tb_bandlimit_engine.v'; Src=($audioSources + @('sim\gowin_prom_model.v')) }
    $suite += @{ Name='tb_bend_ratio_pipeline'; Top='sim\tb_bend_ratio_pipeline.v'; Src=$audioSources }
    $suite += @{ Name='tb_split_audio_multiplier'; Top='sim\tb_split_audio_multiplier.v'; Src=$audioSources }
    $suite += @{ Name='tb_voice_state_ram'; Top='sim\tb_voice_state_ram.v'; Src=$audioSources }
    $suite += @{ Name='tb_ram_wavetable_engine'; Top='sim\tb_ram_wavetable_engine.v'; Src=($audioSources + @('sim\gowin_prom_model.v')) }
    $suite += @{ Name='tb_wide_master_pair'; Top='sim\tb_wide_master_pair.v'; Src=$audioSources }
    # 27 MHz 单时钟生产档（AUDIO_IF=2）：27e6/9/64 = 46875 Hz，BCK 3.000 MHz，24 位槽。
    $suite += @{ Name='tb_top_i2s_27m'; Top='sim\tb_top_i2s_27m.v'; Src=($audioSources + @('rtl\top.v','sim\gowin_prom_model.v','sim\mcp3208_model.v')) }
    # P0 选表语义、P1 音区/阶段、CH9350L HID 链路（2026-10-19）。
    $suite += @{ Name='tb_generic_bright'; Top='sim\tb_generic_bright.v'; Src=@('rtl\audio\shared_wavetable_engine.v',
                'rtl\audio\gowin_prom_guitar_bank.v','rtl\audio\gowin_prom_wave_sine.v','rtl\audio\gowin_prom_bright_bank.v','rtl\audio\gowin_prom_piano_bank.v','sim\gowin_prom_model.v') }
    $suite += @{ Name='tb_piano_stage'; Top='sim\tb_piano_stage.v'; Src=@('rtl\audio\shared_wavetable_engine.v',
                'rtl\audio\gowin_prom_guitar_bank.v','rtl\audio\gowin_prom_wave_sine.v','rtl\audio\gowin_prom_bright_bank.v','rtl\audio\gowin_prom_piano_bank.v','sim\gowin_prom_model.v') }
    $suite += @{ Name='tb_host_kbd'; Top='sim\tb_host_kbd.v'; Src=@('rtl\audio\kbd_uart_rx.v','rtl\audio\ch9350_rx.v','rtl\audio\hid_keymap.v','rtl\audio\host_kbd_input.v') }
    # HID 控制补齐：F6 乐器切换、Up/Down 主音量、Esc 清音，以及与 UART 命令共存。
    $suite += @{ Name='tb_top_host_ctrl'; Top='sim\tb_top_host_ctrl.v'; Src=($audioSources + @('rtl\top.v','sim\gowin_prom_model.v','sim\mcp3208_model.v')) }
    $suite += @{ Name='tb_event_prefetch'; Top='sim\tb_event_prefetch.v'; Src=($audioSources + @('rtl\top.v','sim\gowin_prom_model.v')) }
    $suite += @{ Name='tb_ram32_complete'; Top='sim\tb_ram32_complete.v'; Src=($audioSources + @('rtl\prototypes\voice_sched32.v','rtl\prototypes\ram32_top.v','rtl\prototypes\instrument_rom_banks.v','rtl\prototypes\instrument_ram_audio_datapath.v','rtl\prototypes\instrument_ram_audio_compute.v','rtl\prototypes\instrument_ram_wavetable_engine.v','sim\gowin_prom_model.v','sim\i2s_rx_model.v')) }
    $suite += @{ Name='tb_instrument_rom_banks'; Top='sim\tb_instrument_rom_banks.v'; Src=@('rtl\prototypes\instrument_rom_banks.v','rtl\audio\gowin_prom_piano_bank.v','rtl\audio\gowin_prom_guitar_bank.v','rtl\audio\gowin_prom_bright_bank.v','sim\gowin_prom_model.v') }
    $suite += @{ Name='tb_voice_sched32_review'; Top='sim\tb_voice_sched32_review.v'; Src=@('rtl\prototypes\voice_sched32.v','rtl\audio\note_phase_inc.v') }
    # Product regressions for the eight-voice profiles must run at the same
    # gate as the older four-voice benches.
    foreach ($name in @('tb_engine8_pitch','tb_top_pitch8','tb_top_switch','tb_top_guitar','tb_guitar_bank')) {
        $suite += @{ Name=$name; Top=('sim\'+$name+'.v'); Src=($audioSources + @('rtl\top.v','sim\gowin_prom_model.v','sim\mcp3208_model.v')) }
    }
    foreach($voices in @(8,32,64)) {
        $suite += @{ Name=('tb_ram_audio_datapath_'+$voices); Top='sim\tb_ram_audio_datapath.v'; Src=($audioSources + @('sim\gowin_prom_model.v','sim\i2s_rx_model.v')); Voices=$voices }
    }
    # HDMI dashboard modules are independent of the audio datapath and run as
    # their own self-checking benches.
    $suite += @{ Name='tb_hdmi_timing'; Top='sim\tb_hdmi_timing.v'; Src=@('rtl\video\hdmi_720p_timing.v') }
    $suite += @{ Name='tb_ui_status_export'; Top='sim\tb_ui_status_export.v'; Src=@('rtl\video\ui_status_export.v') }
    $suite += @{ Name='tb_ui_audio_visual_export'; Top='sim\tb_ui_audio_visual_export.v'; Src=@('rtl\video\ui_audio_visual_export.v') }
    $suite += @{ Name='tb_dashboard'; Top='sim\tb_dashboard.v'; Src=@(
        'rtl\video\dashboard_text_mux.v','rtl\video\dashboard_renderer.v',
        'rtl\video\dashboard_font_prom.v','sim\gowin_prom_model.v') }

    $failed = 0
    $skipped = 0
    # Fail before compilation if the checkout is incomplete. A missing bench
    # is a broken gate, never evidence that the corresponding behavior passed.
    $missing = @($suite | Where-Object { -not (Test-Path -LiteralPath $_.Top -PathType Leaf) })
    if (-not (Test-Path -LiteralPath 'sim\tb_i2s_tx_params.v' -PathType Leaf)) {
        Write-Output '缺失参数负例测试台：sim\tb_i2s_tx_params.v；禁止烧录。'
        exit 1
    }
    if ($missing.Count -ne 0) {
        foreach ($entry in $missing) { Write-Output ("缺失测试台：{0}" -f $entry.Top) }
        Write-Output ("仿真门禁不完整，缺失 {0} 台，禁止烧录。" -f $missing.Count)
        exit 1
    }
    foreach ($test in $suite) {
        $out = Join-Path $BuildDir ("{0}.vvp" -f $test.Name)
        Write-Output ("=== {0} ===" -f $test.Name)
        if ($SkipAudioCapture -and $test.Name -eq 'tb_audio_capture') {
            Write-Output '跳过 tb_audio_capture（已单独完成，使用 -SkipAudioCapture）'
            $skipped++
            continue
        }
        # -DSIMULATION 打开 i2s_tx 的参数合法性检查（综合时该块被忽略）。
        # Explicit root prevents uninstantiated library prototypes from being
        # elaborated as extra tops requiring unrelated primitive models.
        $testModule = [System.IO.Path]::GetFileNameWithoutExtension($test.Top)
        $compileArgs = @('-g2012', '-DSIMULATION', '-s', $testModule, '-I', '.', '-o', $out, $test.Top) + $test.Src
        # The newer top/shared-engine tests need both generated pROM banks.
        $usesSharedEngine = @($test.Src | Where-Object { $_ -match '(shared_wavetable_engine\.v|top\.v)$' }).Count -gt 0
        if ($usesSharedEngine) {
            foreach ($rom in @('rtl\audio\gowin_prom_piano_bank.v','rtl\audio\gowin_prom_guitar_bank.v')) {
                $romName = Split-Path -Leaf $rom
                $alreadyPresent = @($test.Src | Where-Object { (Split-Path -Leaf $_) -eq $romName }).Count -gt 0
                if (-not $alreadyPresent) { $compileArgs += $rom }
            }
        }
        if($test.Name -eq 'tb_bandlimit_engine_wide') { $compileArgs=@('-Ptb_bandlimit_engine.EXTRA=2')+$compileArgs }
        if($test.ContainsKey('Voices')) { $compileArgs=@('-Ptb_ram_audio_datapath.VOICES='+$test.Voices)+$compileArgs }
        & $Iverilog @compileArgs
        if ($LASTEXITCODE -ne 0) {
            Write-Output ("编译失败：{0}" -f $test.Name)
            $failed++
            continue
        }

        if ($test.Name -eq 'tb_audio_capture') {
            & $Vvp $out "+CAPTURE_DIR=$AudioCaptureDir"
        } elseif ($test.Name -eq 'tb_i2s_tx') {
            & $Vvp $out "+METRICS_FILE=$(Join-Path $MetricsDir 'tb_i2s_tx_metrics.json')"
        } else {
            & $Vvp $out
        }
        if ($LASTEXITCODE -ne 0) {
            Write-Output ("仿真失败：{0}" -f $test.Name)
            $failed++
        }
    }

    # S3 参数负例：每一例都必须编译通过、运行以非零退出，并且给出匹配的原因。
    $paramCases = @(
        @{ Name = 'zero_clk';        Define = 'S3_CASE_ZERO_CLK';
           Reason = 'S3_PARAM_INVALID: CLK_HZ must be greater than 0' },
        @{ Name = 'zero_fs';         Define = 'S3_CASE_ZERO_FS';
           Reason = 'S3_PARAM_INVALID: SAMPLE_RATE_HZ' },
        @{ Name = 'not_divisible';   Define = 'S3_CASE_NOT_DIVISIBLE';
           Reason = 'S3_PARAM_INVALID: CLK_HZ not divisible' },
        @{ Name = 'frame_not_div64'; Define = 'S3_CASE_FRAME_NOT_DIV64';
           Reason = 'S3_PARAM_INVALID: FRAME_CYC not divisible by 64' },
        @{ Name = 'bck_too_fast';    Define = 'S3_CASE_BCK_TOO_FAST';
           Reason = 'S3_PARAM_INVALID: BCK_CYC must be at least 2' },
        @{ Name = 'data_bits_32';    Define = 'S3_CASE_DATA_BITS_32';
           Reason = 'S3_PARAM_INVALID: DATA_BITS must be 16 or 24' }
    )
    foreach ($case in $paramCases) {
        $out = Join-Path $BuildDir ("tb_i2s_tx_params_{0}.vvp" -f $case.Name)
        Write-Output ("=== tb_i2s_tx_params[{0}] （预期失败）===" -f $case.Name)
        $compileLog = (& $Iverilog '-g2012' '-DSIMULATION' ("-D" + $case.Define) '-I' '.' '-o' $out `
            'sim\tb_i2s_tx_params.v' 'rtl\audio\i2s_tx.v' 2>&1 | Out-String)
        $compileExit = $LASTEXITCODE
        if ($compileExit -ne 0) {
            Write-Output ("参数负例编译失败：{0}（工具问题不是预期失败）" -f $case.Name)
            Write-Output $compileLog
            $failed++
            continue
        }
        $caseLog = (& $Vvp $out 2>&1 | Out-String)
        $caseExit = $LASTEXITCODE
        $caseLog | Set-Content -LiteralPath (Join-Path $MetricsDir ("param_{0}.log" -f $case.Name)) -Encoding UTF8
        if ($caseExit -eq 0) {
            Write-Output ("参数负例 {0} 退出码为 0：非法参数没有被拦截" -f $case.Name)
            $failed++
            continue
        }
        if ($caseExit -ne 1 -or $caseLog -notmatch 'FATAL:' -or
            $caseLog -notmatch [regex]::Escape($case.Reason)) {
            Write-Output ("参数负例 {0} 退出码 {1}，但原因不匹配，期望包含：{2}" -f
                          $case.Name, $caseExit, $case.Reason)
            $failed++
            continue
        }
        Write-Output ("参数负例 {0} 按预期被拒绝（退出码 {1}，原因匹配）" -f $case.Name, $caseExit)
    }

    if ($failed -ne 0) {
        Write-Output ("仿真门禁未通过，{0} 个测试台失败，禁止烧录。" -f $failed)
        exit 1
    }
    if ($skipped -ne 0) {
        Write-Output ("本次 {0} 台正向测试台与 {1} 个参数负例通过，显式跳过 {2} 台；不构成完整烧录门禁。" -f
                      ($suite.Count - $skipped), $paramCases.Count, $skipped)
    } else {
        Write-Output ("全部 {0} 台正向测试台与 {1} 个参数负例通过，允许进入烧录流程。" -f
                      $suite.Count, $paramCases.Count)
    }
    exit 0
}
finally {
    Pop-Location
}
