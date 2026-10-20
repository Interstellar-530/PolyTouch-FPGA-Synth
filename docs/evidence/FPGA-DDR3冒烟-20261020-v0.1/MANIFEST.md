# MANIFEST

- 项目：PolyTouch-FPGA-Synth
- 归档版本：v0.1
- 修改日：2026-10-20
- 阶段：完整采样吉他方案的第一步，DDR3 控制器冒烟验证
- 板卡：Sipeed Tang Primer 20K Dock 3714，GW2A-LV18PG256C8/I7，版本 C
- DDR3：板载 128M DDR3（Sipeed 规格）
- 工具：Gowin V1.9.11.03 Education x64
- 基线仓库：`https://github.com/sipeed/TangPrimer-20K-example`
- 基线提交：`e469df4c0c9c41824f405a8515decf24ef1e8e6f`
- 基线目录：`DDR-test/LicheeTang20K_DDR_Test`
- 许可证：BSD-3-Clause（见 `LICENSE`）
- DDR3 IP：Gowin `DDR3_Memory_Interface_Top` 生成 IP，保存在 `src/ddr3_memory_interface/`

## 目的

验证 Tang Primer 20K Dock 的 DDR3 在当前工具链下能够完成初始化校准、写入和回读，为后续 8 声部吉他采样播放器提供可靠存储底座。

本阶段不包含音频采样、预取 FIFO、Flash 加载或音频输出，也没有修改主项目 `codex/s4-s6-pressure` 的 RTL 或位流。

## 关键文件

- `src/ddr3_smoke_top.v`：冒烟顶层，修正片选连接并增加 N16 校准 LED。
- `src/ddr3_memory_interface/ddr3_memory_interface.v`：Gowin DDR3 控制器生成 IP。
- `src/gowin_rpll/gowin_rpll.v`：27 MHz 到 400 MHz 的 DDR3 PLL。
- `src/tester.v`：Sipeed 原始 DDR3 全片写入/回读测试器。
- `src/uart_tx_V2.v`、`src/print.v`：115200 UART 测试报告。
- `src/ddr3.cst`、`src/ddr3.sdc`：3714 DDR3 引脚和时序约束。
- `build.tcl`、`commands/build.ps1`：复现构建。
- `commands/program_sram.ps1`：上板 SRAM 编程脚本，必须显式 `-SkipSimulation`，仅用于本阶段硬件 bring-up 例外。
- `src/impl/pnr/ddr3_smoke.fs`：生成的位流。
- `src/impl/pnr/ddr3_smoke.rpt.txt`、`ddr3_smoke.timing_paths`：资源和时序证据。

## 构建结果

| 项目 | 结果 |
|---|---|
| Logic | 3320 / 20736（17%） |
| Register | 1926 / 16173（12%） |
| BSRAM | 13 / 46（29%） |
| IOLOGIC | 120 / 207（58%） |
| Setup 最差裕量 | +0.001 ns，0 条负裕量 |
| Hold 最差裕量 | +0.234 ns，0 条负裕量 |
| 位流大小 | 7,264,154 字节 |
| 位流 SHA256 | `0AE0BC3CDD5DE6971EF2F5BB0F7B3DE72074F4FDB9C54CC7E40E7D7946EAD97A` |

Setup 裕量仅 0.001 ns，必须上板验证，不能只凭综合通过宣称 DDR3 可靠。

## 上板状态

尚未上板。当前电脑只识别到 Bluetooth COM3/COM4，没有识别到板卡 USB-JTAG 串口。接板后需要：

1. 用操作 2 烧录 `src/impl/pnr/ddr3_smoke.fs`；
2. 观察 N16 LED 是否在 DDR3 校准完成后点亮；
3. 用 115200 8N1 串口读取测试器的全片写入/回读结果；
4. 把实际串口日志、LED 状态和耗时写入 `evidence/`。

## 后续阶段

1. DDR3 上板校准与读写验收。
2. 采样打包：12 个 44.1 kHz/24 位原始采样裁剪、重采样到 46.875 kHz/16 位，并按 128 位字对齐。
3. 每声部预取 FIFO、DDR3 突发仲裁和 46.875 kHz/100 MHz CDC。
4. 上电加载方案：优先评估 32 Mbit NOR Flash 分区加载，备选 PC/UART。
5. 8 声部线性插值采样播放器、包络、混音和现有 I2S/PT8211 接入。
6. 完整 RTL 门禁、综合、上板音频验收。