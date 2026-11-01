# 复现

在仓库根目录验证发布包：

```powershell
& tools/.venv-docconvert/Scripts/python.exe releases/FPGA-20261030-v0.1/source/verify_release.py
```

也可用任意Python3运行验证脚本，只使用标准库。图稿生成与渲染：

```powershell
& tools/.venv-docconvert/Scripts/python.exe releases/FPGA-20261030-v0.1/source/generate_figures.py
node releases/FPGA-20261030-v0.1/source/render_figures.cjs
```

渲染需要已有Chrome、微软雅黑和 `tools/agent-runtime/node_modules/playwright-core`，这些本机运行环境未提交。其他平台可更换浏览器与字体路径后渲染，但栅格图SHA256会变化，须重新视觉复核和生成校验记录。

最终RTL测试命令如下；Icarus默认位于C:\iverilog。测试工作目录和日志可按本机需要调整，工具不可用时不应宣称通过。

```powershell
& './output/handoff_milestone2_20261008/source/sim/run_simulation.ps1' -Tests @('tb_fsr_sustain','tb_fsr_pedal_latency','tb_fsr_mute','tb_pressure_bend','tb_sustain_pedal','tb_fsr_idle_timeout','tb_fsr_idle_strict') -BuildDir './tmp/daily-20261030-fast' -MetricsDir './tmp/daily-20261030-fast-evidence' -SkipAudioCapture
& './output/handoff_milestone2_20261008/source/sim/run_simulation.ps1' -Tests @('tb_production32') -TimeoutSeconds 300 -BuildDir './tmp/daily-20261030-board' -MetricsDir './tmp/daily-20261030-board-evidence' -SkipAudioCapture
& './output/handoff_milestone2_20261008/source/sim/run_simulation.ps1' -Tests @('tb_dashboard32') -BuildDir './tmp/daily-20261030-ui' -MetricsDir './tmp/daily-20261030-ui-evidence' -SkipAudioCapture
& './output/handoff_milestone2_20261008/source/build/build.ps1' -Profile hdmi
```

如需按成功构建的精确原始字节复现，可将 `source/verified-inputs` 复制到独立目录运行其中的build/build.ps1；其构建脚本按相对位置读取HDL、ROM与约束。收据中的E盘绝对路径保留原始构建来源；本包验证脚本按生产源码根之后的相对路径匹配快照，不依赖原机器盘符。Git源码可能根据本机配置转换换行，需区分字节变化与语义修改。

只有确认目标板卡、引脚与位流SHA256后才执行以下设备命令。operation2是SRAM临时下载，operation37是持久Flash擦写和校验，operation1从Flash重载。

```powershell
$programmerPath = 'E:/Gowin/Gowin_V1.9.11.03_Education_x64/Programmer/bin/programmer_cli.exe'
$fsPath = (Resolve-Path 'releases/FPGA-20261030-v0.1/target/instrument.fs').Path
& $programmerPath --device GW2A-18C --operation_index 2 --cable 'USB Debugger A' --cable-index 1 --frequency 1MHz --fsFile $fsPath
& $programmerPath --device GW2A-18C --operation_index 37 --cable 'USB Debugger A' --cable-index 1 --frequency 1MHz --fsFile $fsPath
& $programmerPath --device GW2A-18C --operation_index 1 --cable 'USB Debugger A' --cable-index 1 --frequency 1MHz
Start-Sleep -Seconds 3
& $programmerPath --device GW2A-18C --operation_index 0 --cable 'USB Debugger A' --cable-index 1 --frequency 1MHz
```

预期User Code为0x00002626、Status为0x00006020。Flash写入必须检查Program and Verify flash successfully；不能只看进程退出码。回退需显式选择旧位流重新写Flash，断电不会恢复旧Flash版本。
