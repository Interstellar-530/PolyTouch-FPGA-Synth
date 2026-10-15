# S5 压力滤波与持续弯音独立复核（2026-10-15）

本记录复核 `output/handoff_milestone2_20261008/source` 中 S5 的三件交付物：`rtl/audio/pressure_bend.v`、`tools/pressure_bend_ref.py`、`sim/tb_pressure_bend.v`，交付说明见 `../s5-pressure-bend.md`。依据是任务清单 S5 的自检标准（0-4095、阶跃/斜坡/单点尖峰逐值对照；无回绕且有界；记录 90% 阶跃响应；压力不改音高；电位器改变持音频率不重启包络；初始 ±2 半音/中位回正；压力关闭仍可演奏）以及定点参考实现本身。工具为本机 MSYS2 UCRT64 的 Icarus Verilog 13.0 与 Anaconda Python 3.13，日志在 `logs/`，整包门禁日志在 `gate-20261015.log`。

## 结论

交付版压力侧的定点实现是正确的，弯音侧存在两处必须修正的问题，另有若干覆盖率与文档一致性问题。逐值对照后确认：交付版 `pressure_bend_ref.py` 在弯音负半程按“负值向下取整”计算，而 RTL 按 Verilog 无符号除法“对幅值截断”，两者在 4096 个 ADC 码中有 4608 个比较点（弯音 Q8、Q16 比率、相位增量三类合计）不一致，最典型的是 ADC=1 时 RTL 给 -511、参考给 -512；交付版自检只采样了 0、2048、4095 三个弯音点，恰好都落在两者重合的位置，所以没能发现。清单要求的“0-4095 逐值对照”在交付版里没有实现，只有少量硬编码期望值，本轮补齐为 640 个压力 tick 加 4096 个弯音 ADC 码的全量对照。此外弯音相位乘法依赖 Verilog 的上下文位宽来决定乘积宽度，属于工具相关写法；比例锚点注释声称是 `2^(n/12)` 的四舍五入值，实际 +1/+2 半音偏低约 0.77/0.75 音分。

## 判定与证据

压力滤波（三点中值 + `y += (median-y) >>> 1`）与参考实现逐值一致，640 个 tick（含 8 拍零、满幅上/下阶跃、128 拍斜坡、中值静止、孤立尖峰、固定种子伪随机尾段）全部相等，日志 `logs/post-fix-tb_pressure_bend.log`。参考同时以不钳位方式重算整条序列，越界次数为 0，说明该递推本身就固守在 0..4095，RTL 里的显式钳位只是防御性写法。90% 阶跃响应由向量回放直接测出：第 5 个控制 tick 越过 3686，即 2 kHz 节拍下约 2.5 ms，与交付说明一致。

弯音映射的取整差异是本次的主要发现。交付版参考的负半程写作 `-((ADC_CENTER - x) * BEND_Q8_MAX) // ADC_CENTER`，在 Python 里先取负再整除，得到的是“幅值向上取整”，而 RTL 的 `(ADC_CENTER - bench) * 512 / 2048` 是无符号整除，即“幅值向下截断”。把交付版参考生成的向量喂给交付版 RTL，得到 4608 条失败，例如 `bend q8 at adc=1: dut=-511 ref=-512`、`bend phase at adc=1: dut=891311 ref=891113`，日志 `logs/control-prereview-reference.log`。由于正半程两边都是非负整除、天然一致，负半程才暴露出方向差别，因此统一为“幅值向下截断”（与 RTL 一致，也与正半程规则一致）后，4096 个 ADC 码的 Q8、Q16 比率与相位增量全部逐值相等。端点与中点同时核验：0 → -512、2048 → 0、4095 → +512，即 ±2 半音与中位回正满足。

压力不改音高与压力关闭可演奏两条也补了直接证据：在弯音固定于中点的条件下把压力从 0 扫到 4095（步长 7，共 586 点），`phase_inc_out` 全程恒等于基准值；`pressure_enable=0` 时 `pressure_level` 为 0 且相位不变；在压力关闭、gate 拉高的条件下让 ADSR 连走两个采样节拍，`env` 继续增长且不回到 idle。持音状态下改变弯音不重触发包络由 ADSR 检查覆盖：弯音更新后 `env` 继续上升、`idle` 保持为 0。

测试检出能力用两项故障注入验证。把 RTL 的有符号右移 `>>>` 改成逻辑右移 `>>`，压力序列出现 613 条失败；把参考的负半程改回交付版的取整方向，弯音出现 4608 条失败。两项都返回退出码 1，说明新的逐值对照不是“只会在正确实现上通过”的空测试。

## 修改内容

| 文件 | 修改 | 依据 | 回退 |
| --- | --- | --- | --- |
| `rtl/audio/pressure_bend.v` | 半程分母改为由 `ADC_CENTER` 推导的 localparam（含零值守护），默认参数下行为不变；相位乘法改为显式加宽操作数；修正比例锚点注释并说明与 `2^(n/12)` 的偏差 | 参数化中点与工具无关的乘积宽度 | 用 `baseline/pressure_bend.v` 覆盖后重跑单台测试 |
| `tools/pressure_bend_ref.py` | 负半程改为“幅值向下截断”以与 RTL 一致；新增 `--vectors DIR` 向量生成、比例锚点偏差报告、不钳位越界计数 | 逐值对照与本记录的证据 | 用 `baseline/pressure_bend_ref.py` 覆盖 |
| `sim/tb_pressure_bend.v` | 重写为向量回放：640 个压力 tick 与 4096 个弯音 ADC 码逐值对照，另加多基频相位对照、压力扫描音高不变、压力关闭仍可演奏、t90 判定、200 ms 超时保护 | 任务清单“0-4095 逐值对照” | 用 `baseline/tb_pressure_bend.delivery-rev-5973.v` 覆盖（该副本是交付版 21:58 修订，见下文基线说明） |
| `sim/vectors/`（新增） | `pressure_inputs/expected`、`bend_q8/ratio/phase_expected` 与 `meta.json`，由参考生成并随交付物固定 | 让门禁可直接逐值对照 | 删除目录并回退 tb |
| `sim/run_simulation.ps1` | 表头说明改为逐值对照口径 | 与 tb 一致 | 回退该行 |
| `rtl/README.md` | `pressure_bend.v` 条目补充逐值对照口径与向量重生成命令 | 模块索引需要与交付物一致 | 回退该条 |

向量校验值（`vector-meta.json` 内同源）：`pressure_inputs.hex` 27cd1bb8…、`pressure_expected.hex` d7a64d75…、`bend_q8_expected.hex` 87706e33…、`bend_ratio_expected.hex` 90e99f42…、`bend_phase_expected.hex` 1a02acd8…。

## 未覆盖与风险

比例锚点仍沿用交付版的五个数值，只是把注释改成与事实一致：-2 半音 +0.417 音分、-1 半音 +0.007 音分、0 音分、+1 半音 -0.772 音分、+2 半音 -0.746 音分，整个弯音范围偏差不超过 0.8 音分。如果需要锚点严格等于 `2^(n/12)` 的四舍五入值，把表改成 58386/61858/65536/69433/73562 即可，本轮未改数值以免改变已交付行为。

尚未做综合与 PnR。`bend_pos_num / BEND_POS_DEN` 是全模块唯一的真实除法，`base_phase_inc * bend_ratio_q16` 是一个 32×17 乘法，两者都是资源热点，建议在下一次综合报告中记录 LUT/DSP 占用，必要时把除法换成倒数乘或小型查找表。这里提醒一点：把 `/2047` 简化成 `(x*1025)>>12` 之类的乘法并非等价，实测 2048 个取值中有 255 个不符，替换前必须做全量对照。

控制节拍定为 2 kHz、音频 48 kHz 迁移时，中值窗口与 IIR 时间常数都要重新核对；FSR 与电位器的机械范围、ADC 参考电压、真实音高偏差与包络延迟仍属 T04 实机验收内容。交付说明里“本机 MSYS2 环境 Icarus 驱动生成 VVP 后报告 access violation -1073741819”同样不准确，原因见 S4 复核记录：把 `msys64\ucrt64\bin` 放进 PATH 后 `iverilog` 与 `vvp` 都能干净退出 0。

## 基线说明

`baseline/pressure_bend.v` 与 `baseline/pressure_bend_ref.py` 取自交付会话的写入记录（会话 rollout 中保存的原始写入内容），与复核开始前磁盘上的文件在关键标记上逐条一致（例如 RTL 的 `32'd2047`、`pressure_diff >>> 1`、比例表注释；参考的 `RATIO_Q16` 与负半程原写法）。`baseline/tb_pressure_bend.delivery-rev-5973.v` 是同一写入记录里的 tb 修订（152 行），复核开始前磁盘上的最终修订为 159 行/6292 字节，两者只差单点尖峰检查块（最终版把窗口写成 `1999..2016` 并多四行说明），该最终修订未能在本地会话记录中找到原文，故以本副本加此说明代替。下一轮 S6 复核会先取基线副本再动文件。

## 复现命令

```powershell
$env:PATH = 'D:\NanjingUniversity\FPGA\msys64\ucrt64\bin;' + $env:PATH
Set-Location output/handoff_milestone2_20261008/source

# 参考自检与向量重生成（修改参考后必须重跑，向量要与参考同源）
python tools/pressure_bend_ref.py --self-test
python tools/pressure_bend_ref.py --vectors sim/vectors

# 单台 S5 自检
iverilog -g2012 -I . -o sim/tb_pressure_bend.vvp sim/tb_pressure_bend.v rtl/audio/pressure_bend.v rtl/audio/adsr.v
vvp sim/tb_pressure_bend.vvp

# 完整门禁（14 台）
pwsh -NoProfile -File sim/run_simulation.ps1 `
  -Iverilog D:\NanjingUniversity\FPGA\msys64\ucrt64\bin\iverilog.exe `
  -Vvp D:\NanjingUniversity\FPGA\msys64\ucrt64\bin\vvp.exe
```