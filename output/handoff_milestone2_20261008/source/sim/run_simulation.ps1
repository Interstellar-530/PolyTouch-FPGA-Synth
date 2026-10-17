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
    [string]$BuildDir = ''
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

$iverilogCandidates = @('C:\iverilog\bin\iverilog.exe')
$vvpCandidates = @('C:\iverilog\bin\vvp.exe')
foreach ($pf in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
    if ($pf) {
        $iverilogCandidates += (Join-Path $pf 'iverilog\bin\iverilog.exe')
        $vvpCandidates += (Join-Path $pf 'iverilog\bin\vvp.exe')
    }
}

if (-not $Iverilog) { $Iverilog = Find-Tool -Name 'iverilog' -FromEnv $env:IVERILOG -Candidates $iverilogCandidates }
if (-not $Vvp)      { $Vvp      = Find-Tool -Name 'vvp'      -FromEnv $env:VVP      -Candidates $vvpCandidates }

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
                'rtl\audio\global_crossfade.v', 'rtl\audio\i2s_tx.v',
                'rtl\audio\gowin_prom_wave_sine.v', 'rtl\audio\gowin_prom_wave_bright.v',
                'sim\gowin_prom_model.v', 'sim\mcp3208_model.v') },
        @{ Name = 'tb_s6_rom_prim'; Top = 'sim\tb_s6_rom_prim.v'; Src = @(
                'rtl\audio\wavetable_osc_dual_s6.v', 'rtl\audio\wavetable_osc_dual_prom.v',
                'rtl\audio\gowin_prom_wave_sine.v', 'rtl\audio\gowin_prom_wave_bright.v',
                'sim\gowin_prom_model.v') },
        @{ Name = 'tb_shared_engine'; Top = 'sim\tb_shared_engine.v'; Src = @(
                'rtl\audio\shared_wavetable_engine.v', 'rtl\audio\global_crossfade.v',
                'rtl\audio\wavetable_osc_dual_s6.v', 'rtl\audio\gowin_prom_wave_sine.v',
                'rtl\audio\gowin_prom_wave_bright.v', 'sim\gowin_prom_model.v') }
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
                'rtl\audio\shared_wavetable_engine.v', 'rtl\audio\global_crossfade.v',
                'rtl\audio\i2s_tx.v', 'rtl\audio\gowin_prom_wave_sine.v',
                'rtl\audio\gowin_prom_wave_bright.v', 'sim\gowin_prom_model.v',
                'sim\mcp3208_model.v', 'sim\i2s_rx_model.v') }
    )

    # Shared board controls are required by every bench containing rtl/top.v.
    foreach ($entry in $suite) {
        if ($entry.Src -contains 'rtl\top.v') { $entry.Src += 'rtl\audio\instrument_controls.v' }
    }
    $audioSources = @(Get-ChildItem -LiteralPath 'rtl/audio' -Filter '*.v' | ForEach-Object FullName)
    foreach ($name in @('tb_timbre_controls','tb_timbre_audio','tb_timbre_uart','tb_timbre_top')) {
        $suite += @{ Name=$name; Top=('sim\'+$name+'.v'); Src=($audioSources + @('rtl\top.v','sim\gowin_prom_model.v','sim\mcp3208_model.v','sim\i2s_rx_model.v')) }
    }

    foreach ($name in @('tb_architecture_equivalence','tb_shared_bend_equivalence','tb_bend_equivalence','tb_shared_master')) {
        $suite += @{ Name=$name; Top=('sim\'+$name+'.v'); Src=($audioSources + @('sim\gowin_prom_model.v','sim\reference\baseline_shared_wavetable_engine.v','sim\reference\baseline_pressure_bend.v')) }
    }
    foreach ($name in @('tb_headroom','tb_bend_precision','tb_adc_reset_top')) {
        $suite += @{ Name=$name; Top=('sim\'+$name+'.v'); Src=($audioSources + @('rtl\top.v','sim\gowin_prom_model.v','sim\mcp3208_model.v')) }
    }

    $failed = 0
    foreach ($test in $suite) {
        $out = Join-Path $BuildDir ("{0}.vvp" -f $test.Name)
        Write-Output ("=== {0} ===" -f $test.Name)

        # -DSIMULATION 打开 i2s_tx 的参数合法性检查（综合时该块被忽略）。
        $compileArgs = @('-g2012', '-DSIMULATION', '-I', '.', '-o', $out, $test.Top) + $test.Src
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
    Write-Output ("全部 {0} 台正向测试台与 {1} 个参数负例通过，允许烧录。" -f
                  $suite.Count, $paramCases.Count)
    exit 0
}
finally {
    Pop-Location
}
