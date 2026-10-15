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
## 第二增量：S4/S5/S6 接进顶层（2026-10-15）

**做了什么**。新增 `rtl/audio/poly_voice_s6.v`：双波表声部（32 位相位累加 + `wavetable_osc_dual_s6` + ADSR + 力度缩放），不改动已验证的 `poly_voice`。`rtl/top.v` 增加 MCP3208 SPI 端口与 2 kHz 控制节拍，CH0/CH1 轮流采样，`pressure_bend` 取弯音比率，四个声部改用 `poly_voice_s6`（声部 0 直接用 `pressure_bend` 的输出，其余三路各一次显式加宽的 32×17 乘法），混音换成 `mixer_s6`（`VOLUME_SHIFT=1` 与旧 `mixer` 的“求和除二”一致，FIR 默认旁路），并新增 `clip_fold[3:0]` 折叠观测输出。四个既有顶层测试接入 `mcp3208_model`（CH1 保持中点 2048，比率恰为 1.0，因此原有音频期望不变）。新增 `sim/tb_top_s4s6.v`：两个通道都被轮询、弯音逐值映射（0→-512/58400、2048→0/65536、4095→+512/73530、1024→-256/61858）、压力不改变音高与增量、折叠输出不留 X。约束补上 SPI 引脚（N6/D11/A11/B11）与 `clip_fold` 草稿引脚，新增 `build/build_top_integrated.tcl`。

**集成期又抓到三个问题**。其一，`adc_channel <= ~adc_channel[0]` 被上下文补成 3 位，实际得到 6/7 通道，ADC 一直在问 CH6/CH7，压力与弯音从未更新；改成显式 1 位 `adc_sel` 后两路都正确。这是本仓库第三次踩 Verilog 上下文位宽坑（S5 的相位乘法、S4 注释里的 32/48 位积、这次的通道选择），值得当作编码规范条目。其二，我用脚本编辑 `top.v` 时再次写入 UTF-8 BOM，Icarus 会跳过整个文件并报 “Unable to find the root module”，上一版记录里已提示过，说明编辑脚本必须显式禁止 BOM。其三，我的测试台生成脚本把行尾写成 `\r\r\n`，导致后续按 CRLF 锚点的补丁全部失配，已统一回 CRLF。

**Gowin 结果（集成顶层，实测，非估算）**

| 资源 | 用量 | 占比 |
| --- | ---: | ---: |
| Logic（2596 LUT + 872 ALU） | 3516 / 20736 | 17% |
| Register | 1128 / 16173 | 7% |
| BSRAM（全部为 pROM） | 8 / 46 | 18% |
| DSP（17 个 MULT18X18 + 12 个 PADD18） | 18.5 / 24 | 78% |
| I/O | 34 / 207 | 17% |

时序：setup 与 hold 违例均为 0、TNS 为 0，最差 setup slack +12.575 ns，工具报告 fmax 约 40.9 MHz（约束 27 MHz）。综合日志确认四张波表都落在 BSRAM/pROM，没有退化成 LUT ROM。

关键结论是 DSP 预算：4 个 S6 声部已经用掉 **78% 的 DSP**（每声部 4 次 ROM 读 + 2 次混合乘法 + 包络/力度乘法），BSRAM 8 块。要扩到 8/32 声部必须做共享——把双表读取与插值改成时分复用，并把交叉混合从“每声部”改成“两组声部求和后混合一次”（全局音色权重时数学等价），可以省掉每声部两次混合乘法。

**门禁**：19 台正向测试台加 6 个参数负例全部通过，退出码 0，日志 `logs/gate-integration.log`；Gowin 报告副本在 `reports/`。一处代价需要记住：S6 振荡器每个时钟读 4 个表项，`tb_audio_capture` 这类长仿真比之前慢约一倍；把 `en` 改成“每次 sample_tick 后两个时钟的脉冲”即可把读次数降三个数量级（功能等价、未在本增量实施）。

**仍未完成**：`i2s_tx` 接顶层与标准 I2S 约束（等 12.288 MHz 晶振）；显式 BSRAM/pROM 原语替换与仿真等价比对；运行时可调音色与压力路由（当前固定 25% 明亮混合，压力只进折叠观测）；共享引擎（8/32 声部）；以及全部实机验收项。

## 第三增量：显式 pROM 原语（综合侧完成，仿真等价受阻）

**已完成**。`tools/gen_gowin_prom_init.py` 按 UG285 §3.4 的 pROM 约定生成两张表的显式原语封装：`BIT_WIDTH=16` 得到 1024 深地址空间，512 个样本放在 `INIT_RAM_00..1F`（每个 256 位字装 16 个样本，样本 i 位于第 `i%16` 个 16 位槽），源 hex 的 SHA256 与初始化字摘要写进 `gowin_prom_meta.json`；生成 `rtl/audio/gowin_prom_wave_sine.v`、`gowin_prom_wave_bright.v`。`rtl/audio/wavetable_osc_dual_prom.v` 是与 `wavetable_osc_dual_s6` 契约相同的 pROM 版振荡器（pROM 的 bypass 读自带一级寄存，插值与混合口径逐位照抄）。`rtl/synth_s6_prom_harness.v` 加 `build/build_s6_prom_harness.tcl` 与草稿 CST 组成测量顶层，Gowin 综合 + 布局布线 + 时序 + 位流全部通过（退出码 0）：

| 资源（四声部 pROM 版） | 用量 | 占比 |
| --- | ---: | ---: |
| Logic | 698 / 20736 | 4% |
| Register | 183 / 16173 | 2% |
| **BSRAM（全部为 pROM）** | **16 / 46** | **35%** |
| DSP（8 个 MULT18X18） | 10 / 24 | 42% |

结论：**显式原语被综合器接受并确实映射到块存储**，不再依赖“行为数组被推断成 BSRAM”这条隐含路径，第三增量的主要目标达成。报告副本 `reports/pnr_prom_harness.rpt.txt`。

**受阻**：行为版与 pROM 版的逐值等价测试 `sim/tb_s6_rom_prim.v`（512 地址 × 5 小数位 × 3 种混合 = 7680 点）目前失败，pROM 版输出恒为 0。用厂商 `prim_sim.v` 里的 `pROM` 模型单独探针验证：无论地址、位宽接法还是 32 位全宽 `DO`，读回都是 0，说明这个放在 IP 测试台目录下的模型并不能作为 pROM 的功能模型使用（它虽然声明了 `INIT_RAM_xx` 参数并按 `{INIT_RAM_3F..00}` 组成 16K 位向量，但读通路在 Icarus 下不产生数据）。因此“我的 INIT 字序是否正确”这件事**还没有被独立验证**。下一步有两条可走：一是改用 IP Core Generator 生成的 pROM IP（自带仿真模型与 .ini/hex 初始化文件），二是先用一个只写一个字的极小例子确认字序，再回到等价测试。

**资源对比的注意点**：本次 pROM 版每个声部用了 4 个独立 ROM（相邻地址各一个），所以是 16 块；行为版是 8 块。把相邻地址合并进双端口块、或按 512×36 把两张表打包，预计能回到每声部 1–2 块，这一步属于下一步的优化，不能拿这两组数字直接对比。

**共享引擎原型**（求和后全局交叉混合 + 双表读取时分复用）尚未开始，仍按第二增量末尾的计划执行。

## 第三增量（续）：pROM 地址/字序问题的定位与解决

**根因**。厂商模型 `prim_sim.v` 里 pROM 的实现显示：`BIT_WIDTH=16` 时字地址取 `AD[13:4]`（`AD[3:0]` 被忽略），也就是说 AD 要按“位地址”风格给出，即 `AD = {addr, 4'b0000}`。我最初的生成封装把字地址放在低位（`{5'b0, addr}`），于是模型/器件永远读第 0 个字；而正弦表第 0 个样本恰好是 0，所以最早的探针看起来像“厂商模型不工作”。这一结论是从厂商模型源码逐行读出来的，不是猜测：`addr = {AD[13:4], 4'b0000}`、`mem_t[15:0] = ram_MEM[addr+15 : addr]`、`ram_MEM = {INIT_RAM_3F, …, INIT_RAM_00}`，因此样本 k 位于第 k/16 个 256 位字的第 (k%16) 个 16 位槽（低位在前）——正是生成器采用的槽位顺序。

**修正**。`tools/gen_gowin_prom_init.py` 改为 `AD = {1'b0, addr, 4'b0000}` 并重新生成两个封装；修正后 pROM 版综合/PnR 重跑仍然通过（Logic 698、Register 183、BSRAM 16/46 全部 pROM、DSP 10/24）。

**等价性验证通过**。`sim/tb_s6_rom_prim.v`（512 地址 × 5 个小数位 × 3 种混合设置 = 7682 个比较点）在两套模型上分别通过：用厂商 `prim_sim.v` 交叉核对，以及用新入库的 `sim/gowin_prom_model.v`（按厂商模型语义实现，注释里写明依据；供门禁在不依赖未入库厂商文件的情况下运行）。两次输出都是
`PASS tb_s6_rom_prim: pROM and behavioural wavetable ROM agree on 7682 comparisons`。

**门禁**。该测试加入队列后，整轮为 **20 台正向测试台加 6 个参数负例，退出码 0**，日志 `logs/gate-integration.log`；pROM 版报告副本 `reports/pnr_prom_harness.rpt.txt`。

**仍未做**。ROM 块数优化（当前每声部 4 个独立 ROM = 16 块；把相邻地址合并进双端口块或按 512×36 打包两张表，预计回到每声部 1–2 块），以及共享引擎原型（双表读取时分复用 + 求和后全局交叉混合）。

## 第四增量：共享引擎原型（未通过等价测试，如实归档）

**目标**：做共享引擎原型——双表读取时分复用 + 两组声部求和后全局交叉混合——并配一对同架构测量顶层做资源对比，给出与逐声部混合的等同性证据（含舍入偏差界）。

**已建立**

- `rtl/audio/shared_wavetable_engine.v`：4 个声部共用 1 个 sine ROM 与 1 个 bright ROM；相位累加器在模块内；一条 FSM（每声部 15 拍、整机 60 拍，预算 576 拍）按时分复用完成“读相邻地址 -> 9 位插值 -> 包络缩放 -> 力度缩放 -> 累加”；全模块**只写一条乘法表达式**（操作数逐拍由 mux 装入），因此综合后只有一组共享乘法器。输出两条 19 位分量和。
- `rtl/audio/global_crossfade.v`：把两条分量和按 `(255-w, w) >> 8` 混合一次，再做与 `mixer_s6` 相同的除二与 16 位饱和。
- `sim/tb_shared_engine.v`：10 个用例（5 个权重 × 2 组相位/包络/力度），分两部分断言——(a) 引擎的 `sine_sum`/`bright_sum` 必须与“行为版 S6 振荡器（纯分量）-> 包络 -> 力度”逐声部求和**逐位相等**；(b) 逐声部混合后求和与全局混合的最终 16 位输出之差不超过 `BOUND = 2`（舍入从每声部一次变为整机一次）。

**调试进展与当前状态**。用一个逐拍打印内部状态的探针（已删除，临时文件不入库）定位并修掉两处时序错位：`rom_ce` 原先用寄存器输出，导致地址比 CE 晚一拍、首次读捕到 0；`a`/`b` 捕获点与 pROM 的一拍读延迟不对齐。修正后 sine 分量和从“完全错误”收敛到 44188，对参考 44958 仍有 1.7% 偏差；bright 分量仍然错（72807 对参考 22034），因此 **`tb_shared_engine` 仍为 FAIL**，并**没有加入门禁**。

**结论**：共享引擎的架构、验证框架与探针手段都已就位，但引擎本身**尚未通过等价测试**，不能当作可用的音频路径。剩余问题集中在 bright 通道的捕获/地址对齐以及 sine 的 1.7% 残差，下一步用同一探针按通道逐拍核对（预计是一次对齐修正），通过后再做那对同架构测量顶层的资源对比——引擎没通过之前给出资源数字没有意义。

**未做**：同架构资源对比（依赖引擎通过）；ROM 块数优化（当前每声部 4 块，目标 1–2 块）。**门禁不受影响**，仍为 20 台正向 + 6 个参数负例通过。

## 第四增量（续）：共享引擎通过等价测试，资源对比完成

**引擎修好了**。三个 bug 依次定位并修掉：其一，`rom_ce` 原是寄存器输出，地址比 CE 晚一拍，首次读捕到 0；其二，`b` 的读取窗口没被 CE 覆盖（CE 少了 `ST_ADDR_B`），`b` 捕到的是 `a` 的值；其三，也是最关键的一条——共享乘法器每拍都做 `mul_p <= mul_a * mul_b`，因此某个状态装入的操作数要到**两拍之后**才能读乘积（X 装入 → X+1 操作数生效 → X+2 乘积可用），我原本早用了一拍。补上 6 个等待态后：

```text
PASS tb_shared_engine: 15 cases, component sums bit-exact, global crossfade within 2 LSB
```

即：15 个用例（5 个权重 × 3 组相位/包络/力度，其中第三组专门用非零小数位压插值路径）下，引擎的两条**分量和与逐声部参考逐位相等**，而“先求和后全局混合”与“逐声部混合后求和”的最终 16 位输出差不超过 **2 LSB**（舍入从每声部一次变为整机一次）。该测试已加入门禁。测试台还顺手修掉一个自身缺陷：原先的 10 个用例小数位全是 0，根本没压到插值路径，现已补上带小数的一组。

**资源对比（同架构一对测量顶层，Gowin 综合 + PnR + 时序 + 位流全部通过）**

| 资源 | 逐声部架构 | 共享引擎架构 | 变化 |
| --- | ---: | ---: | --- |
| Logic | 739（4%） | 713（4%） | 略降 |
| Register | 141（<1%） | 431（3%） | +290（FSM 与时分复用控制） |
| **BSRAM** | **16/46（35%）** | **2/46（5%）** | **8 倍下降**（整机 2 块 = 每声部 0.5 块） |
| **DSP** | **13.5/24（57%）** | **2/24（9%）** | **约 6.8 倍下降** |

两个顶层功能等价（差别仅上文那 ≤2 LSB 的舍入位置，以及 ROM/插值/混合的组织方式），报告副本在 `reports/pnr_voices_per_voice.rpt.txt` 与 `reports/pnr_voices_shared.rpt.txt`，构建日志 `logs/gowin_voice_variants.log`。这也顺带完成了上一轮遗留的“ROM 块数从每声部 4 块降到 1–2 块”目标——共享架构做到每声部 0.5 块，比原目标更好。

**仍未做**：把共享引擎接入产品顶层（当前顶层仍用逐声部 `poly_voice_s6`）；共享版没有 FIR/削波统计（全局混合模块未接 `mixer_s6`，接顶层时需要补上）；共享版是否满足时序余量要等接入顶层后再看一次报告；实机验收项不变。

## 第五增量：共享引擎接入产品顶层 + 一次真实缺陷的复核（2026-10-15）

**目标**：把共享引擎真正接到产品顶层，同时保住 S1 音频验收基线（抽样抓取 + 独立 PCM/FFT 判据），并给出接入后的资源与时序。

**顶层改动**

- `rtl/top.v`：四个 `poly_voice_s6` 换成「4 × `adsr` + `v_pending`/`v_retrig`（start 暂存到 `sample_tick`，与 `poly_voice_s6` 同一口径）+ `shared_wavetable_engine` + `global_crossfade`」。逐声部 `vs0..vs3` 与其驱动逻辑删除。
- `mixer_s6` 退出产品顶层：它的两项职责（四路求和 + `VOLUME_SHIFT=1` 主增益、采样帧寄存器边界）现在都由 `global_crossfade` 在同一处完成一次，顶层再串一级只会多出一拍延迟与一份死逻辑。`mixer_s6` 与它的 (1,4,6,4,1) FIR 仍留在库里并由 `tb_s6_audio` 覆盖。FIR 仍旁路（启用会把 10 kHz 压到约 −8.5 dB，音频验收基线要重做）。
- `rtl/audio/global_crossfade.v`：补上**主增益边界的削波统计**（`clip_count` 饱和到全 1、`clip_event` 每帧一次、`clear_clip` 同步清零），语义与 `mixer_s6` 的文档定义一致。上一增量遗留的“共享版没有 FIR/削波统计”到此关闭。
- `global_crossfade` 的更新节拍改接引擎 `sums_valid`（帧内有效），不再等下一个 `sample_tick`：产品通路因此比逐声部链路**少一帧（约 21.3 µs）延迟**，对音高与频谱无影响，逐值对照见下。
- 门禁与构建脚本同步：`sim/run_simulation.ps1` 的 5 处顶层源文件表换成共享引擎/pROM，`sim/tb_shared_engine.v` 增加削波统计断言与一个故意过载用例（16 用例），`build/build_top_integrated.tcl` 补入引擎与 pROM 文件（旧工程目录要先删掉再重建，tcl 只在工程不存在时添加文件）。

**复核发现一（我自己引入的中间态错误）**。顶层切到共享引擎后，`mixer_s6` 实例还在吃已被删除驱动的 `vs0..vs3`。Verilog 允许隐式连线，编译不报错，但无驱动网络是 X，整条音频通路随之变 X：`tb_audio_capture` 在 clk 66760 报 `Unknown audio pin or sample_tick`，用探针确认 `frame_data=xxxx` 而 `mixed_shared=0000`。已在同一次工作里改掉（mixer 退出顶层、削波统计迁到 `global_crossfade`）。

**复核发现二（引擎的真实缺陷，关键）**。`shared_wavetable_engine.v` 把 16 位有符号的 `scaled_s`/`scaled_b` 用 `{13'd0, scaled_s}` 拼进 19 位累加器：**拼接结果是无符号的，`$signed()` 无法还原符号**，于是 −20840 变成 +44744，输出因此带上约半个满量程的直流。逐拍探针实测 `sine_acc=44696`（正是 −20840 的无符号回绕），独立抓取频谱显示单音直流 +16311、和弦直流 +32013，chord4 四个基频被压到 870–930 LSB（验收判据 ≥1000 LSB），S1 音频验收直接 FAIL。

这个缺陷此前没被发现，是因为 `tb_shared_engine` 的参考模型写成 `ref_sine_sum = {13'd0, voice_out(...)} + ...`，**与引擎犯了同一个错误**：两边都丢符号，误差互相抵消，所以 15 个用例全绿。修复方式是在引擎里显式符号扩展（`scaled_s_ext`/`scaled_b_ext`），并把测试台参考侧改成 `ext19()` 函数；修复后用**变异验证**证明测试台不再盲目：

```text
engine=fixed  -> PASS tb_shared_engine: 16 cases ...
engine=HEAD   -> FAIL w=0 sine_sum=102472 ref=-28600
```

**验证证据**

- 完整门禁 exit 0：21 台正向测试台 + 6 个参数负例全绿（`logs/gate-top-shared-engine.log`，末尾为「全部 21 台正向测试台与 6 个参数负例通过，允许烧录」）。
- S1 独立音频验收 PASS（`tools/analyze_audio_capture.py`，原始 WAV/PCM/PNG/JSON 在 `audio-shared-engine/`）：58880 帧，A4 = 440.000000 Hz（误差 2.9e-7 Hz），拟合残差 688 LSB。
- 与逐声部顶层（HEAD 的 `top.v`）逐值 A/B：`a4_steady` 基频 7958.9 LSB、峰值 7731、RMS 5670.4（逐声部同值 7958.9 / 7730 / 5670.4）；`chord4` 四个基频 7966.4 / 7944.6 / 7974.7 / 7968.1（逐声部 7966.3 / 7944.4 / 7975.1 / 7968.7），差 ≤1 LSB。缺陷前后的完整数据见 `reports/audio-signext-defect-evidence.txt`。
- Gowin 综合 + PnR + 时序 + 位流全部通过（`reports/pnr_instrument_shared_engine.rpt.txt`、`reports/timing_summary_instrument_shared_engine.txt`、`logs/gowin_top_shared_engine_build.log`）：0 条 setup/hold 违例，TNS 0，实际 Fmax 46.368 MHz（约束 27 MHz，逻辑级数 18）。

| 资源 | 逐声部顶层（56577e3） | 共享引擎顶层（本次） | 变化 |
| --- | ---: | ---: | --- |
| Logic | 3516（17%） | 3776（19%） | +260（FSM 与时分复用控制） |
| Register | 1128（7%） | 1460（10%） | +332 |
| **BSRAM** | **8/46（18%）** | **2/46（5%）** | **4 倍下降** |
| **DSP** | **18.5/24（78%）** | **6.5/24（28%）** | **约 2.8 倍下降** |

**仍未做**：`i2s_tx` 接顶层与标准 I2S 约束（等 12.288 MHz 晶振）；运行时可调音色与压力路由；实机验收（T04）。共享引擎的第二条 ROM 端口与 FIR 是否回归，等实机有音频后再定。