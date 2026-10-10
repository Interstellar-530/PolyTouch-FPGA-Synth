# 交接包说明

这个文件夹是 2026-10-08 的 FPGA 电子乐器项目交接快照，里面有：

- 已经能综合通过的 RTL；
- Gowin 构建、JTAG 扫描和 SRAM 烧录脚本；
- 正常单声部码流 `artifacts/instrument.fs`；
- 带 GAO 核的调试码流 `artifacts/ao_0.fs`；
- 综合、资源、时序、引脚和功耗报告；
- GAO 配置 `source/rtl/gao_top.rao`；
- 调试日志 `reference/logs/FPGA_DEBUG_LOG_20261008.md` 和 PDF；
- 比赛规则、原理图、板卡数据和项目规划资料；
- 给队友 AI 的接管说明。

## 队友的 AI 第一步应该读

```text
START_HERE_FOR_AI.md
PROJECT_MANIFEST.json
CURRENT_STATUS.md
NEXT_TASKS.json
CHANGELOG.md
```

不要先读 `reference/`。那里是历史资料，可能包含旧电脑的绝对路径。

## 重新构建

进入 `source/build` 后运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build.ps1
```

如果脚本没有自动找到 Gowin，可以传入 `-GwSh`，或者设置环境变量
`GOWIN_GW_SH`。当前推荐使用 Tcl 构建，因为 Gowin IDE 直接综合仍可能找不到
`wave_sine.hex`。

## 烧录

先用命令行扫描下载器：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scan_jtag.ps1
```

烧录 SRAM 时使用操作 2，不要使用带 Verify 的操作：

```powershell
& 'E:\Gowin\Gowin_V1.9.11.03_Education_x64\Programmer\bin\programmer_cli.exe' `
  --device GW2A-18C --operation_index 2 `
  --fsFile '..\..\artifacts\instrument.fs'
```

`SRAM Program and Verify` 在这块板子上会报 `Verify Failed`，状态码
`0x00006020`。烧录 SRAM 后不要断电。

## LED 和音频预期

正常码流 `artifacts/instrument.fs` 会让 Orange_LED2、N16 约每 1 秒闪烁一次，
同时耳机口输出 440 Hz、0.25 秒通断的调试音。没有耳机时，可以使用有源音箱、
电脑 line-in、逻辑分析仪或 Gowin GAO 观察。

## GAO 观察

独立 `gao_analyzer.exe` 在当前环境里无法稳定打开，请使用 Gowin IDE 内置
GAO。打开 `source/build/gowin_single_voice/instrument/instrument/instrument.gprj`
后，在 Design 窗口双击 `source/rtl/gao_top.rao`，连接 Local jtagserver，
Cable 选 `Gowin USB Cable(FT2CH)`，Device chain 选 Gowin Device、Series
`GW2A`、Device `GW2A-18C`。`ao_0.fs` 已写入 SRAM 时，取消 `Enable
Programmer`，或者把操作选成 `SRAM Program`。

## 2026-10-10 Key and Volume Test
- Default output is A4 440 Hz.
- Press the first non-reset user key T3 to switch to C4 261.63 Hz.
- Press the second non-reset user key T2 to switch to C5 523.25 Hz.
- S0/T10 is reset and must not be used as a tone key.
- Volume is reduced by about 12 dB; adjust VOLUME_SHIFT in top.v if needed.
