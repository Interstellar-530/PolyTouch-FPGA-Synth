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
`GOWIN_GW_SH`。默认生成普通码流 `source/impl/pnr/instrument.fs`；加上
`-Gao` 会使用独立工程生成 GAO 码流 `source/impl/pnr/ao_0.fs`。
普通和 GAO 工程已分离，直接 IDE 综合的波表 include path 也已修复。

## 烧录

先用命令行扫描下载器：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scan_jtag.ps1
```

烧录 SRAM 时使用操作 2，不要使用带 Verify 的操作：

```powershell
& 'E:\Gowin\Gowin_V1.9.11.03_Education_x64\Programmer\bin\programmer_cli.exe' `
  --device GW2A-18C --operation_index 2 `
  --fsFile '..\impl\pnr\instrument.fs'
```

`SRAM Program and Verify` 在这块板子上会报 `Verify Failed`，状态码
`0x00006020`。烧录 SRAM 后不要断电。

## LED 和音频预期

正常码流 `artifacts/instrument.fs` 会让 Orange_LED2、N16 约每 1 秒闪烁一次，
同时耳机口输出 440 Hz、0.25 秒通断的调试音。没有耳机时，可以使用有源音箱、
电脑 line-in、逻辑分析仪或 Gowin GAO 观察。

## GAO 观察

`gao_analyzer.exe` 需要 `-gao`、`-family`、`-device` 参数。直接在
`source/build` 下运行下面命令，脚本会补齐参数并打开 GAO 捕获界面：

```powershell
.\launch_gao.ps1
```

如果板卡还未加载 GAO 码流，用操作 2 烧录 `source/impl/pnr/ao_0.fs`：

```powershell
.\program_sram.ps1 -FsFile '..\impl\pnr\ao_0.fs'
```

然后连接 Local jtagserver，Cable 选 `Gowin USB Cable(FT2CH)`，Device chain
选 Gowin Device、Series `GW2A`、Device `GW2A-18C`。Gowin IDE 内置 GAO
仍然可以作为备用方案。
