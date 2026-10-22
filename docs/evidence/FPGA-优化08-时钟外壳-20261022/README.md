# 优化 08：12.288 MHz 时钟外壳（2026-10-22）

对应规划文件 [FPGA-12.288MHz晶振倍频与时序重构建议](../../planning/FPGA-12.288MHz晶振倍频与时序重构建议-20261022-v0.1.md)
的批次 A，以及其后的批次 C（73.728 MHz 主档）。目标是把单时钟原型改成
“12.288 MHz 音频参考域 + rPLL 计算域 + 带确认的立体声帧桥”，并验证 4/6/8 倍频档位。

## 原指标（改前）

| 项 | 数值 |
|---|---|
| 时钟结构 | `ram32_top` 单时钟，`CLK_HZ` 写死 49.152 MHz，I2S 与计算同域 |
| PLL | `audio_pll_clock` 固定 4 倍（49.152 MHz） |
| 帧桥 | `audio_frame_bridge` 单声道、toggle 无接收确认 |
| 资源/Fmax | Logic 5367、Register 2468、BSRAM 26、DSP 1；Fmax 60.110 MHz（49.152 约束） |

## 方法

1. **PLL 参数化**：`audio_pll_clock #(.MULT(4/6/8))`，IDIV=1、FBDIV=MULT、ODIV=16（4 倍）或 8（6/8 倍）；
   VCO 分别 786.432 / 589.824 / 786.432 MHz。
2. **立体声帧桥**：`audio_frame_bridge_stereo`，参考域给出 48 kHz 帧沿；
   计算域返回 `{frame_id, left, right}` 原子包，保持到参考域确认（ack）后才允许更新。
3. **双时钟顶层**：`ram32_clocked_top`，参考域跑 I2S，计算域跑调度器/RAM 引擎/宽主混合；
   事件经四相握手跨域（请求→锁存→就绪→确认），慢控制经两级同步。
4. **73.728 MHz 收敛**：把乘法器输出的 51 位舍入加法改成窄位加法
   （`(p+K)>>S` 只加输出所需的低位），去掉 DSP 输出到下一级寄存器的长进位链；
   声音逐位不变（161 样本最大差 0）。

## 最终指标

| 检查项 | 结果 |
|---|---|
| PLL 三档 | 49.154 / 73.725 / 98.309 MHz；每 256 个参考周期 1024 / 1536 / 2048 个计算沿 |
| 双时钟功能（4/6/8 倍） | 32 声部分配、I2S 立体声一致、帧号递增、释放后 31 声部，全部通过 |
| 73.728 MHz PnR | **Fmax 73.730 MHz**（约束 73.728），TNS 0，clk_ref 域 TNS 0 |
| 73.728 MHz 时序 | setup 最差 +0.035 ns（非负），15–17 级；hold 通过 |
| 资源 | Logic **5351/20736 (26%)**、Register **2614/16173 (17%)**、BSRAM **26/46**、DSP **1/24** |

说明：73.728 MHz 的 setup 余量只有 +0.035 ns，满足“非负”的通过条件，但未达到建议的
+0.5 ns 设计目标。若要更厚余量，下一步是把调度器“音符→增量”快照再寄存一级（当前最差路径
`note → cfg_inc_q`，17 级），代价是快照多 1 拍、帧内多约 32 拍，1536 拍帧完全放得下。

98.304 MHz 只做了功能仿真（`tb_ram32_clocked` MULT=8 通过），未做 PnR；按规划批次 E 延后。

## 资源占用情况对比

| 资源 | 单时钟（改前） | 双时钟外壳（73.728 档） |
|---|---:|---:|
| Logic | 5367 | **5351** |
| Register | 2468 | **2614** |
| BSRAM | 26 | **26** |
| DSP | 1 | **1** |
| Fmax | 60.110 MHz @49.152 | **73.730 MHz @73.728** |

寄存器增加 146 个（事件握手、帧桥、两级同步、PLL 复位释放），逻辑基本持平。

## 复现

```powershell
cd output\handoff_milestone2_20261008\source
$lib = 'E:\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\simlib\gw2a\prim_sim.v'
# PLL 三档
C:\iverilog\bin\iverilog.exe -g2012 -DSIMULATION -s tb_audio_pll_mult -I . `
  -o ..\..\..\tmp\pll.vvp sim\tb_audio_pll_mult.v rtl\audio\audio_pll_clock.v $lib
C:\iverilog\bin\vvp.exe ..\..\..\tmp\pll.vvp
# 双时钟顶层（MULT=4/6/8）
C:\iverilog\bin\iverilog.exe -g2012 -DSIMULATION -s tb_ram32_clocked "-Ptb_ram32_clocked.MULT=6" `
  -I . -o ..\..\..\tmp\clocked.vvp <见 build/ram32_clocked.tcl 的源码列表> $lib
C:\iverilog\bin\vvp.exe ..\..\..\tmp\clocked.vvp
# PnR
$env:FPGA_BUILD_RUN_DIR = 'E:\Working Space\FPGA\tmp\ram32_clocked_run'
& 'E:\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\bin\gw_sh.exe' build\ram32_clocked.tcl
```

## 文件

- `source/`：PLL、立体声帧桥、双时钟顶层/包装、两个测试台
- `pll_mult.log`、`clocked_4/6/8.log`：PLL 与双时钟功能日志
- `build_reports/`：73.728 MHz PnR 资源、Fmax、时序
- `commands/`：PnR TCL 与 12.288 MHz 约束

## 附：73.728 MHz 余量加厚尝试（2026-10-22 下午）

为把 setup 余量从 +0.035 ns 做厚，试验了两条不改数学的路径，均因不满足验收而回退：

| 方案 | 结果 | 结论 |
|---|---|---|
| A. 调度器快照拆两级（先锁存字段，再算增量） | 帧末仍 576/606，但输出与基线**非延迟对齐**：161 样本最大差 63880 | 配置呈现相对帧边界偏移，声音改变；回退 |
| B. 每声部预存 32 位增量，快照只读数组 | 寄存器 +1024，Fmax **68.612 MHz**、TNS **−225 ns / 539 端点** | 额外寄存器带来的布局压力大于缩短查找链的收益；回退 |

保留已验证版本：Fmax 73.730 MHz、TNS 0、setup +0.035 ns。若要把余量做到 +0.5 ns，
需要把“音符→增量”整体移出快照路径且保持配置时序，或接受一拍配置延迟并用定时对齐
（而非逐位一致）比较验证；这属于下一轮决策。