# S6 双波表、同步 ROM 与混音独立复核（2026-10-15）

本记录复核 `output/handoff_milestone2_20261008/source` 中 S6 的交付物：
`rtl/audio/wavetable_rom_dual.v`、`rtl/audio/wavetable_osc_dual_s6.v`、
`rtl/audio/mixer_s6.v`、`sim/tb_s6_audio.v`、`rtl/audio/wave_sine.hex`、
`rtl/audio/wave_bright.hex`、`tools/generate_wavetables.py`、
`tools/s6_reference.py` 与交付说明 `../s6-audio.md`。依据是任务清单 S6 的
自检标准（两表各 512 点、同步读延迟、相位环绕/插值与参考一致、切换/混合
可控、四路同相正负极值正确饱和不回绕、clip 统计准确、FIR 旁路/启用延迟和
频响有记录）以及项目规则中“波表必须使用 Gowin BSRAM ROM IP 或原语”的约束。
工具为本机 MSYS2 UCRT64 的 Icarus Verilog 13.0 与 Anaconda Python 3.13，
日志在 `logs/`，门禁日志在 `gate-20261015.log`。交付版八件文件在改动前已
原样存入 `baseline/`。

## 结论

两张表、同步 ROM 契约、插值（含 511→0 接缝）、表选择与交叉混合、四路极值
饱和、clip 计数与清零都验证正确，但 **`mixer_s6.v` 的五抽头 FIR 中抽头写成
了 8 而不是文档所述的 6**，实际系数是 (1,4,8,4,1)/16：直流增益 18/16 =
1.125，阶跃响应出现过冲（62、312、812、1062、1125，稳态 1125 而非 1000），
46.875 kHz 采样率下 1 kHz 处是 +0.95 dB 的抬升而不是低通应有的轻微衰减，
把 FIR_ENABLE 打开会让同一素材整体抬高约 1.02 dB，并让本不该削波的信号进入
削波（例如幅度 29127 的信号经该滤波器变成 32767，修正后仍为 29127）。交付版
自检只用了已削波到 ±32767 的满幅输入（此时两版都饱和到同一值），所以没能
发现。本轮把中抽头改为 6，并把 FIR 纳入逐值对照。

除该缺陷外，交付版符合 S6 验收标准；需要补的是覆盖率与记录：交付版自检只有
少量硬编码点位，`tools/s6_reference.py` 完全不覆盖混音器的 FIR，FIR 的群延迟
与频响也没有记录。本轮补齐了这些内容，14 台门禁通过。

## 判定与证据

两张表可复现且取值合法：重新运行 `tools/generate_wavetables.py` 后
`wave_sine.hex` 与 `wave_bright.hex` 的 SHA-256 与交付说明记录的
`b75030d2…`、`c16616d4…` 完全一致，两表各 512 项、取值 -32767..32767，
日志 `logs/delivered-generate-wavetables.log`。正弦表保持 v1.0.0 基线，亮音色
表由 1/k 加权的 16 次谐波生成，最高分音 C5×16=8.37 kHz 低于当前 46.875 kHz
与目标 48 kHz 两种采样率的奈奎斯特频率。

同步 ROM、插值、混合与混音器全部改为与 `tools/s6_reference.py` 生成的向量
逐值对照，日志 `logs/post-fix-tb_s6_audio.log`：3584 个相位点（全部 512 个
地址 × 7 个分数，其中 frac=2 与 4 专门命中 `(diff*frac) mod 512 == 256` 的
取整平局条件）、1024 个 ROM 交叉混合点（4 个地址 × 全部 256 个权重）、256 个
插值后交叉混合点、510 个混音器样本（VOLUME_SHIFT 0/1/2 × FIR 旁路/启用，
逐个核对饱和输出、每帧 clip_event 与累计 clip 计数）、32 个 FIR 小幅度样本
（验证单位直流增益）。相位环绕由 511→0 接缝点覆盖（`idx_b` 依赖 9 位地址宽度
自然回绕，与参考的 `(idx+1) & 0x1FF` 一致）。

FIR 缺陷用故障注入确认可检出：把 `mixer_s6.v` 换成交付版（中抽头 8），同一
组向量出现 240 条失败，全部落在 FIR 启用的分块里，例如
`mixer vec 85 shift=0 fir=1: dut=32751 ref=28655`，日志
`logs/control-delivered-fir-tap.excerpt.log`。另有取整敏感性对照：把插值
舍入常数由 `+256` 改成 `+255`，在补入平局分数后出现 12 条失败（如
`osc sine phase=0c008000: dut=9513 ref=9514`），日志
`logs/control-interp-rounding.log`，说明该对照能分辨 1 LSB 级差异。

## FIR 延迟与频响记录

旁路路径在采样节拍上寄存一拍，输出帧与当前输入帧对齐；启用 FIR 后，中抽头落在
`d2`（即 x[n-2]），群延迟为 2 个采样帧，比旁路多 2 帧，当前 46.875 kHz 下
42.7 µs、目标 48 kHz 下 41.7 µs。修正后的 (1,4,6,4,1)/16 频响（
`tools/s6_reference.py` 的 `meta.json` 一并报出）：

| 频率 | 46.875 kHz 采样 | 48 kHz 采样 |
| ---: | ---: | ---: |
| 1 kHz | -0.08 dB | -0.07 dB |
| 5 kHz | -1.99 dB | -1.89 dB |
| 10 kHz | -8.47 dB | -8.04 dB |
| 15 kHz | -21.68 dB | -20.42 dB |
| 20 kHz | -51.31 dB | -46.96 dB |

交付版的 (1,4,8,4,1)/16 在同一张表上是 +0.95、-0.72、-5.98、-13.66、
-17.87 dB（46.875 kHz），即低频抬升、阻带衰减更差，这个差别是复核时要盯住
的信号。clip 统计点仍在主增益边界（FIR 之前），因此 FIR 后的饱和不会重复
计数，也不会掩盖上游的 raw clip。

## 修改内容

| 文件 | 修改 | 依据 | 回退 |
| --- | --- | --- | --- |
| `rtl/audio/mixer_s6.v` | FIR 中抽头 8 → 6（`2*d2 + 4*d2`）并加注释说明缺陷后果 | 交付说明与标准二项式 (1,4,6,4,1)/16 的单位增益 | 用 `baseline/mixer_s6.v` 覆盖 |
| `tools/s6_reference.py` | 扩展为逐值参考与向量生成器：插值/混合/混音/FIR 模型、向量与元数据（含频响与群延迟）、自检含 FIR 单位增益断言 | 清单要求“与参考一致”“频响有记录” | 用 `baseline/s6_reference.py` 覆盖 |
| `sim/tb_s6_audio.v` | 保留交付版定性检查，另加 3584+1024+256+510+32 个向量逐值对照、clip 计数逐向量核对、超时提到 2 ms | 清单逐值对照要求 | 用 `baseline/tb_s6_audio.v` 覆盖并删除 `sim/vectors/` |
| `sim/vectors/`（新增） | 22 支向量与 `meta.json` | 同上 | 删除目录 |
| `tools/generate_wavetables.py` | 未改（脚本本身可复现且有校验），只在复核记录中登记结果 | 复核确认无缺陷 | 不适用 |

## 未覆盖与风险

波表仍是行为级数组，`wavetable_rom_dual.v` 与 `wavetable_osc_dual_s6.v` 的
注释都标明生产实现必须替换为 Gowin BSRAM/pROM IP；本轮没有做综合与 PnR，
厂商原语验证仍未完成，与任务清单“未接厂商模型时标记未完成”的口径一致。
资源方面：每个 ROM 实例占 2 块 BSRAM（512×16），振荡器里有两对 27×27 乘法
（插值）与两对 25×25 乘法（混合），ROM 模块另有 2 个 25×25 乘法，建议在下
一次综合报告里记录 DSP/LUT 占用。

`DEPTH` 参数只用于数组尺寸，地址回绕依赖 `phase[31:23]` 恰好 9 位；把
`DEPTH` 改成非 512 的值会静默破坏接缝插值，生产前要么固定 512，要么把
`idx_b` 显式取模。交叉混合采用 `(255-w, w) >> 8`，端点比纯表值低 1/256
（满幅最多 128 LSB，约 -0.034 dB），因此 `mix_enable=1` 且权重取端点时与
`mix_enable=0` 的纯表输出有微小台阶；这是 8 位权重的取舍，本轮只记录未改，
如果要端点严格相等需要 16 位权重或对端点特殊处理。

FIR 群延迟与旁路不同（2 帧对 0 帧），顶层接入 I2S 时要么把两种路径的帧对齐
一并考虑，要么把 FIR 固定启用。交付说明中“MSYS2 Icarus 额外返回
`-1073741819`”的说法与前两轮复核结论一致地不准确：把
`msys64\ucrt64\bin` 放进 PATH 后 `iverilog` 与 `vvp` 都干净退出 0。

## 复现命令

```powershell
$env:PATH = 'D:\NanjingUniversity\FPGA\msys64\ucrt64\bin;' + $env:PATH
Set-Location output/handoff_milestone2_20261008/source

# 表与参考
python ../../../tools/generate_wavetables.py        # 从仓库根运行时用 tools/...
python ../../../tools/s6_reference.py --vectors sim/vectors

# 单台 S6 自检
iverilog -g2012 -I . -o sim/tb_s6_audio.vvp sim/tb_s6_audio.v `
  rtl/audio/wavetable_rom_dual.v rtl/audio/wavetable_osc_dual_s6.v rtl/audio/mixer_s6.v
vvp sim/tb_s6_audio.vvp

# 完整门禁（14 台）
pwsh -NoProfile -File sim/run_simulation.ps1 `
  -Iverilog D:\NanjingUniversity\FPGA\msys64\ucrt64\bin\iverilog.exe `
  -Vvp D:\NanjingUniversity\FPGA\msys64\ucrt64\bin\vvp.exe
```

## 基线说明

本轮在改动前先把交付版八件文件（三个 RTL、测试台、两个工具脚本、交付说明、
两张表）复制到 `baseline/`，因此所有差异都可逐条回退；这也是 S5 复核留下的
流程教训。