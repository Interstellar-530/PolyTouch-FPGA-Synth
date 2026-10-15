# S4–S6 并入 S1–S3 线：集成与 Gowin 隔离综合/PnR（2026-10-15）

本记录是“Gowin 原语与顶层集成”的第一增量。基线选 `codex/s3-i2s-tx@17aff2d`——它是更完整的一条线（顶层已含 S2 的 12 路 GPIO 琴键与独立的手动事件 FIFO，S3 的 `i2s_tx` 与参数负例已单独验收，并自带 Gowin 构建/PnR 与证据）。S4–S6 的交付物此前只存在于 `fix/m2-build-issues` 这条较旧的基线上，因此本增量先把它们并入 S3 线，再谈原语与顶层。

## 已完成

**一、S4–S6 并入并跑通整线门禁。** 并入 5 个 RTL 模块、6 个测试台、31 支向量、3 个工具脚本、三份复核记录与日志；门禁从 13 台扩到 **18 台正向测试台 + 6 个参数负例**，一次通过、退出码 0，日志 `logs/gate-integration.log`。覆盖范围：S1 的真实音频捕获（58880 帧、独立 PT8211 解码）、S2 的 `tb_gpio_keyboard`/`tb_gpio_top`、S3 的 `tb_i2s_tx`（四组合）与六个非法参数、以及 S4 的三台与 S5、S6 各一台。

**二、集成期发现并修掉三个真实问题。**

1. `rtl/top.v` 里 `demo_mode`、`pending_valid`、`pending_word` 声明在首次使用之后；Icarus 13 直接拒绝精化（`Unable to bind wire/reg/memory 'demo_mode'`），S2/S3 线之所以没暴露，是因为那份证据用 **Icarus 12.0 (dev, 2015)** 跑的。已把三个声明前移到 `man_wr` 之前，逻辑不变；这也让该线在本机 Icarus 13 上可复现。
2. 两张波表在 S3 线上是 CRLF、在 S4–S6 线上是 LF，抽样内容完全相同（512 点、min/max 一致、逐样本相等）。统一为 LF，并把 `*.hex text eol=lf` 并入既有 `.gitattributes`，这样文档记录的 SHA-256 在任何签出下都成立。
3. 本增量过程中我一度给 top.v 写入 UTF-8 BOM，Icarus 会因 BOM 完全跳过该文件（报 `Unable to find the root module "top"`）。已去掉并在本记录登记，作为后续编辑 Verilog 的注意点：该仓库的 `.v` 文件保持无 BOM、LF/CRLF 均可。

**三、Gowin 隔离综合与 PnR（只构建，未烧录）。** 新增三个文件：`rtl/synth_s4s6_harness.v`（S4–S6 数据通路的测量顶层：2 kHz 控制节拍、MCP3208 双通道轮询、压力/弯音控制路径、四声部双波表振荡器与逐声部弯音乘法、`mixer_s6`；所有被测量信号折进三个 4 位可观测输出，避免综合把未使用的通路裁掉）、`constraints/primer20k_s4s6_harness.cst`（引脚取自项目自己的 `docs/hardware/FPGA-pinplan-20261013-v0.1.csv`，含 MCP3208 的 `adc_cs_n` N6 / `adc_sck` D11 / `adc_mosi` A11 / `adc_miso` B11，十二个折叠输出借用 GPIO 琴键引脚）、`build/build_s4s6_harness.tcl`。`gw_sh` 完成综合 + 布局布线 + 时序分析 + 位流生成，退出码 0，控制台日志 `logs/gowin_s4s6_harness_build.log`，报告副本在 `reports/`。

## 实测资源与时序

| 资源 | 用量 | 占比 |
| --- | ---: | ---: |
| Logic（433 LUT + 532 ALU） | 965 / 20736 | 5% |
| Register（FF） | 500 / 16173 | 4% |
| **BSRAM** | **11 / 46** | **24%** |
| **DSP** | **9 / 24** | **38%** |
| I/O | 18 / 207 | 9% |

时序：`clk_27m` 约束 27 MHz，setup 违例 0、hold 违例 0、TNS 0；最差 setup slack **+19.287 ns**，最差 hold slack **+0.425 ns**（报告 `reports/pnr_harness.rpt.txt`）。

三点值得记录。其一，综合日志明确写着 `Extracting RAM for identifier 'sine_rom'/'bright_rom'`，也就是两张波表的行为级数组已经被 Gowin **推断成 BSRAM**，没有退化成 LUT ROM；所以“波表必须用 BSRAM”这条在推断层面已经满足，显式 BSRAM/pROM 原语或 IP 替换的价值主要在于摆脱推断依赖、让跨工具和跨版本行为确定，而不是修一个 LUT-ROM 缺陷。其二，4 声部就吃掉 11 块 BSRAM（24%）与 9 只 DSP（38%），与计划文本担心的“复制声部会撞器件上限”一致；顺带纠正一处计划数据：本器件（`GW2A-LV18PG256C8/I7`）报告可用 DSP 为 **24** 只，不是计划里写的 48。其三，本增量只证明 S4–S6 能综合、能布线、时序干净，**没有**证明它们与 `top.v` 的音频/事件路径已连好。

## 尚未完成（下一增量）

把 S4/S5/S6 真正接进 `top.v`：2 kHz 控制节拍与 ADC 通道轮询调度、压力与弯音接到声部的相位增量、双波表振荡器替换 `poly_voice` 内的 `dds_osc`（需要一个 `poly_voice_s6` 变体，避免动已验证的 `poly_voice`）、以及 `mixer_s6` 替换现有 `mixer` 以拿到 FIR 与 clip 统计。随后是把 `i2s_tx` 接进顶层并改 CST/SDC（`i2s_bck/lrck/din` 与 12.288 MHz 时钟引脚在 pinplan 里已给出，但标准 48 kHz 档案要等有源晶振到货才能收敛）。最后才是显式 BSRAM/pROM 原语或 IP 替换与仿真等价比对——目前综合已经把它推断成 BSRAM，所以这一步是确定性加固而非功能修复。

## 复现

```powershell
$env:PATH = 'D:\NanjingUniversity\FPGA\msys64\ucrt64\bin;' + $env:PATH
Set-Location output/handoff_milestone2_20261008/source
pwsh -NoProfile -File sim/run_simulation.ps1 `
  -Iverilog D:\NanjingUniversity\FPGA\msys64\ucrt64\bin\iverilog.exe `
  -Vvp D:\NanjingUniversity\FPGA\msys64\ucrt64\bin\vvp.exe
D:\Gowin_V1.9.11.03_Education_x64_win\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\bin\gw_sh.exe `
  build/build_s4s6_harness.tcl
```

## 基线说明

本工作树 `PolyTouch-FPGA-Synth-integration` 是主检出的第二个 worktree，分支 `codex/s4-s6-integration`（起自 `codex/s3-i2s-tx@17aff2d`）。S3 线原有的构建产物目录（`source/impl/`、`build/gowin_poly/`）已被其 `.gitignore` 排除；本增量把新项目目录 `build/gowin_s4s6_harness/` 也加入同样的排除，报告文本另存 `reports/` 入库。