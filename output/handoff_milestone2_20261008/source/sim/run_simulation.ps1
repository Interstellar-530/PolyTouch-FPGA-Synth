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
      tb_gpio_keyboard  [S2] 12 路 GPIO 键的同步/消抖/边沿/背压/flush 与响应上界
      tb_gpio_top       [S2] 顶层模式回归：GPIO 退出演示、四键同拍、Panic 优先
      tb_audio_capture 从真实 PT8211 引脚解码样本；PCM/FFT 另由 tools/run_audio_verification.ps1 验收
#>
param(
    [string]$Iverilog = '',
    [string]$Vvp = '',
    [string]$AudioCaptureDir = '',
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
    if (-not $BuildDir) { $BuildDir = Join-Path $sourceRoot 'sim' }
    New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
    $BuildDir = (Resolve-Path -LiteralPath $BuildDir).Path
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
                'rtl\audio\note_phase_inc.v', 'rtl\audio\event_fifo.v',
                'rtl\audio\voice_alloc.v', 'rtl\audio\song_player.v',
                'rtl\audio\mixer.v', 'rtl\audio\pt8211_tx.v', 'rtl\audio\uart_ctrl.v',
                'rtl\audio\gpio_keyboard.v') },
        @{ Name = 'tb_gpio_top'; Top = 'sim\tb_gpio_top.v'; Src = @(
                'rtl\top.v',
                'rtl\audio\dds_osc.v', 'rtl\audio\adsr.v', 'rtl\audio\poly_voice.v',
                'rtl\audio\note_phase_inc.v', 'rtl\audio\event_fifo.v',
                'rtl\audio\voice_alloc.v', 'rtl\audio\song_player.v',
                'rtl\audio\mixer.v', 'rtl\audio\pt8211_tx.v', 'rtl\audio\uart_ctrl.v',
                'rtl\audio\gpio_keyboard.v') },
        @{ Name = 'tb_poly';        Top = 'sim\tb_poly.v';        Src = @(
                'rtl\top.v',
                'rtl\audio\dds_osc.v', 'rtl\audio\adsr.v', 'rtl\audio\poly_voice.v',
                'rtl\audio\note_phase_inc.v', 'rtl\audio\event_fifo.v',
                'rtl\audio\voice_alloc.v', 'rtl\audio\song_player.v',
                'rtl\audio\mixer.v', 'rtl\audio\pt8211_tx.v', 'rtl\audio\uart_ctrl.v',
                'rtl\audio\gpio_keyboard.v') },
        @{ Name = 'tb_audio_capture'; Top = 'sim\tb_audio_capture.v'; Src = @(
                'rtl\top.v',
                'rtl\audio\dds_osc.v', 'rtl\audio\adsr.v', 'rtl\audio\poly_voice.v',
                'rtl\audio\note_phase_inc.v', 'rtl\audio\event_fifo.v',
                'rtl\audio\voice_alloc.v', 'rtl\audio\song_player.v',
                'rtl\audio\mixer.v', 'rtl\audio\pt8211_tx.v', 'rtl\audio\uart_ctrl.v',
                'rtl\audio\gpio_keyboard.v') }
    )

    $failed = 0
    foreach ($test in $suite) {
        $out = Join-Path $BuildDir ("{0}.vvp" -f $test.Name)
        Write-Output ("=== {0} ===" -f $test.Name)

        $compileArgs = @('-g2012', '-I', '.', '-o', $out, $test.Top) + $test.Src
        & $Iverilog @compileArgs
        if ($LASTEXITCODE -ne 0) {
            Write-Output ("编译失败：{0}" -f $test.Name)
            $failed++
            continue
        }

        if ($test.Name -eq 'tb_audio_capture') {
            & $Vvp $out "+CAPTURE_DIR=$AudioCaptureDir"
        } else {
            & $Vvp $out
        }
        if ($LASTEXITCODE -ne 0) {
            Write-Output ("仿真失败：{0}" -f $test.Name)
            $failed++
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
