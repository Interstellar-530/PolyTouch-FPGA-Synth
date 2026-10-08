# FPGA 电子乐器调试日志

## 基本信息

| 项目 | 内容 |
| --- | --- |
| 日期 | 2026-10-08 |
| 板卡 | Sipeed Tang Primer 20K 核心板 + Dock 3714 |
| FPGA | GW2A-LV18PG256C8/I7，器件版本 C |
| 工作副本 | `E:\Working Space\FPGA\work\handoff_milestone1_20261007\handoff_milestone1_20261007` |
| Gowin | Gowin Education V1.9.11.03 |
| JTAG | Gowin USB Cable(FT2CH)，ID 0x0000081B |

## 当前结论

当前工程的 27 MHz 板载时钟问题已经通过重新拔插核心板解决。用 27 MHz 驱动的四路用户 LED 诊断码流曾经四个灯同时闪烁，说明核心板时钟、FPGA 配置和四个用户 LED 都正常。之后恢复了正常的单声部 DDS、ADSR、PT8211 音频链，并把 LED2 即 Orange_LED2、N16 用作闪烁指示。当前 SRAM 中最后写入的是带 GAO 核的 `ao_0.fs`，User Code 为 `0x0000B32D`。GAO 独立程序不能在这台机器上稳定打开，已经改用 Gowin IDE 内置 GAO 流程。

## 交接包核验

原始交接包 `handoff_milestone1_20261007.zip` 的 50 个登记文件哈希和大小全部匹配，没有缺失或损坏；额外文件只有 `FILE_MANIFEST.json` 自身。工程入口、RTL、约束、构建脚本、综合报告、时序报告、码流和参考原理图都存在。原设计是单声部 DDS、512 点正弦波表、ADSR、27 MHz 调试时钟、PT8211 右对齐输出，调试采样率为 46.875 kHz。

## Gowin 构建问题

直接在 Gowin IDE 中综合时，`dds_osc.v` 的 `$readmemh("rtl/audio/wave_sine.hex")` 找不到文件，导致 ROM 为空，`dds_osc`、`adsr` 和 `voice` 被优化掉。包内 Tcl 构建因为在 `run all` 前执行了 `cd $root`，能够找到相对路径，所以 Tcl 构建正常。IDE 直接构建的问题还没有彻底修复，后续需要用 Gowin ROM IP 或把十六进制文件复制到工程目录并统一路径。构建脚本 `build_instrument.tcl` 中检查 `.gprj` 的路径已经修正，现在可以在已有工程上重新打开并构建。

## LED 与时钟调试

LED 引脚经过 3714 原理图确认：Orange_LED0=C13、Orange_LED1=A13、Orange_LED2=N16、Orange_LED3=N14、Orange_LED4=L14、Orange_LED5=L16。LED 电路是 3.3 V 经 510 Ω 接到 LED 阳极，FPGA 引脚接阴极，低电平点亮。最初 LED2 常亮，是因为 27 MHz 逻辑没有运行，`led_blink` 停在低电平。为了区分时钟问题和灯位问题，先后做了内部 OSC 四灯诊断和 27 MHz 四灯诊断。内部 OSC 诊断四个灯闪烁，证明 FPGA 配置和 LED 电路正常；重新拔插核心板后，27 MHz 四灯诊断也四个灯闪烁，证明板载 27 MHz 恢复。之后恢复为正常单灯版本，只让 Orange_LED2、N16 闪烁。

## 烧录与校验

`SRAM Program and Verify`，也就是 `--operation_index 4`，在这块板子上会报 `Error: Verify Failed`，退出码 18，状态码 `0x00006020`。编程阶段能到 100%，但读回校验失败。`SRAM Program`，也就是 `--operation_index 2`，可以成功写入并返回退出码 0。后续统一使用操作 2，烧录后不要断电，因为 SRAM 配置会丢失。

## 当前可用码流

正常码流是 `source/impl/pnr/instrument.fs`，用途是正常单声部 DDS、ADSR、PT8211 和 LED2 闪烁，User Code 为 `0x00009A0A`。SHA256 为：

```text
e79c1c58b66bc4cff6f4eafb03f51a6c
9b5fc9a73f348420a1cbed23c7d19985
```

GAO 码流是 `source/impl/pnr/ao_0.fs`，用途是带 GAO 核的调试，User Code 为 `0x0000B32D`。SHA256 为：

```text
f637549f363fc23e5fceb29422b2291a
3cb229e56e86145fced257fee6c85ebb
```

旧码流是 `artifacts/instrument.fs`，没有 LED 闪烁。SHA256 为：

```text
dacbbf602cc7c4a00ff3e4381d7fb402
28d742746a4b55aa2512c94f360de591
```

## 代码与工程改动

`source/rtl/top.v` 增加了基于 27 MHz 的 LED 闪烁计数器，最终恢复为 `output wire led` 并连接 Orange_LED2、N16。`source/constraints/primer20k_dock3714.cst` 也恢复为单路 `led` 输出。`source/build/build_instrument.tcl` 修正了 `.gprj` 存在性检查路径。新增 `source/rtl/gao_top.rao`，采样时钟为 `clk_27m`，触发信号为 `sample_tick` 上升沿，捕获 `rst`、`sample_tick`、`gate`、`voice_sample[15:0]`、`hp_bck`、`hp_ws`、`hp_din`、`pa_en` 和 `led`。该 `.rao` 已以 `type="file.gao"` 加入工程文件列表。

## GAO 调试

GAO 核已经成功接入工程，构建日志出现 `Trying to combine GAO to RTL design`，并生成了 `ao_0.fs`。GAO 独立程序 `gao_analyzer.exe` 在当前环境里启动后立即退出，不能单独使用；Gowin IDE 内置 GAO 是可用路径。GAO 需要 Local jtagserver，当前只保留一个 jtagserver 进程，PID 33168。多个 jtagserver 会占用 JTAG，导致 Programmer 报 `Cable failed to open via the channel`。在 GAO 波形窗口里需要把 Cable 设为 `Gowin USB Cable(FT2CH)`，Device chain 设为 Gowin Device、Series 为 GW2A、Device 为 GW2A-18C，并勾选 Enable。由于 `ao_0.fs` 已经写入 SRAM，建议取消 `Enable Programmer`，或者把操作选成 `SRAM Program`，不要使用 `Program and Verify`。

## 当前遗留问题

Gowin IDE 直接综合时仍然可能找不到 `rtl/audio/wave_sine.hex`，当前依赖 Tcl 构建规避。GAO 独立程序不能用，需要在 Gowin IDE 中打开工程后双击 `gao_top.rao`，再打开内置 GAO 捕获窗口。当前 Gowin IDE 进程已经在运行，但停在 Start Page，需要手动打开工程文件。`SRAM Program and Verify` 的读回校验仍然失败，所有烧录使用操作 2。LED2 在原理图上是 N16；如果用户观察的“2号LED”是物理第二个灯，可能是 Orange_LED1 对应的 A13，需要按实际灯位调整。

## 下一步

在 Gowin IDE 中打开 `source/build/gowin_single_voice/instrument/instrument/instrument.gprj`，在 Design 窗口双击 `gao_top.rao`，使用内置 GAO 连接 Local jtagserver，选择 FT2CH 和 Gowin Device GW2A-18C，然后点击 Start 或 Auto 捕获波形。确认 `sample_tick`、`gate`、`voice_sample[15:0]` 和 PT8211 三根信号有变化后，再继续四声部、UART 状态输出和正式 PCM5102A I2S 路径。所有临时构建和渲染文件已经清理，项目 `tmp` 目录为空。
