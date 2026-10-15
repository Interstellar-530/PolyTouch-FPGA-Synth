<#
    RTL 仿真门禁。

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
      tb_mcp3208_spi 覆盖 MCP3208 完整 19 拍 DS21298E 事务、边界码、双通道、固定种子随机值和帧内复位恢复
      tb_mcp3208_i2s_coexist 覆盖 ADC 事务与 PT8211 音频节拍并行、tick 仍为 576 拍
      tb_mcp3208_params 覆盖 27 MHz/250 kHz 生产参数、分频钳位和 SPI_HZ=0 的守护
      tb_pressure_bend 与 Python 参考逐值对照（640 个压力 tick、4096 个弯音 ADC 码）并覆盖 t90、弯音边界和持音不重启
      tb_s6_audio    覆盖双同步 ROM、相位插值/环绕、交叉混音、FIR 和削波计数
#>
param(
    [string]$Iverilog = '',
    [string]$Vvp = ''
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
        @{ Name = 'tb_mode_uart'; Top = 'sim\tb_mode_uart.v'; Src = @(
                'rtl\top.v',
                'rtl\audio\dds_osc.v', 'rtl\audio\adsr.v', 'rtl\audio\poly_voice.v',
                'rtl\audio\note_phase_inc.v', 'rtl\audio\event_fifo.v',
                'rtl\audio\voice_alloc.v', 'rtl\audio\song_player.v',
                'rtl\audio\mixer.v', 'rtl\audio\pt8211_tx.v', 'rtl\audio\uart_ctrl.v') },
        @{ Name = 'tb_poly';        Top = 'sim\tb_poly.v';        Src = @(
                'rtl\top.v',
                'rtl\audio\dds_osc.v', 'rtl\audio\adsr.v', 'rtl\audio\poly_voice.v',
                'rtl\audio\note_phase_inc.v', 'rtl\audio\event_fifo.v',
                'rtl\audio\voice_alloc.v', 'rtl\audio\song_player.v',
                'rtl\audio\mixer.v', 'rtl\audio\pt8211_tx.v', 'rtl\audio\uart_ctrl.v') },
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
                'rtl\audio\mixer_s6.v') }
    )

    $failed = 0
    foreach ($test in $suite) {
        $out = Join-Path $sourceRoot ("sim\{0}.vvp" -f $test.Name)
        Write-Output ("=== {0} ===" -f $test.Name)

        $compileArgs = @('-g2012', '-I', '.', '-o', $out, $test.Top) + $test.Src
        & $Iverilog @compileArgs
        if ($LASTEXITCODE -ne 0) {
            Write-Output ("编译失败：{0}" -f $test.Name)
            $failed++
            Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue
            continue
        }

        try {
            & $Vvp $out
            if ($LASTEXITCODE -ne 0) {
                Write-Output ("仿真失败：{0}" -f $test.Name)
                $failed++
            }
        }
        finally {
            # .vvp files are reproducible build temporaries; keep the source
            # tree clean after both PASS and failure.
            Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue
        }
    }

    if ($failed -ne 0) {
        Write-Output ("仿真门禁未通过，{0} 个测试台失败，禁止烧录。" -f $failed)
        exit 1
    }
    Write-Output "全部测试台通过，允许烧录。"
    exit 0
}
finally {
    Pop-Location
}
