## 范围

S4/S5/S6 三轮独立复核与修正，基线为 `fix/m2-build-issues@3a31eb2`（本分支的直接父提交）。每轮先取交付版基线副本，再修正缺陷、把硬编码点位替换成与 Python 参考逐值对照的向量，并重跑整套仿真门禁。

## 修正的三处缺陷

**S4 MCP3208 SPI：帧少一拍、读回窗口提前一拍。** 交付版只发 18 拍 SCLK 并在第 7～18 个上升沿采样，而 DS21298E 规定起始位之后第 7 拍是器件驱动的 null 位、第 8～19 拍才是 B11..B0，因此真实器件上每个码都会被整体右移一位（4095 读成 2047，`2049` 读成 `1024`）。现改为 19 拍帧、在第 8～19 拍采样、整帧最后一个下降沿提交，`sim/mcp3208_model.v` 按手册时序重写（不再与主机共享假设）。新增 `tb_mcp3208_i2s_coexist.v`（ADC 事务期间音频 tick 仍严格 576 拍）与 `tb_mcp3208_params.v`（27 MHz/250 kHz、分频钳位、`SPI_HZ=0` 守护）。

**S5 压力/弯音：参考与 RTL 在弯音负半程取整方向不一致。** 参考按“负值向下取整”，RTL 的无符号整除按“幅值截断”，4096 个 ADC 码中有 1536 个在 Q8/比率/相位三类比较上不一致（ADC=1 时 RTL 给 −511、参考给 −512）。现两边统一为幅值截断，半程分母由 `ADC_CENTER` 推导并加零值守护，相位乘法显式加宽操作数。`tb_pressure_bend.v` 改为 640 个压力 tick 加 4096 个弯音码逐值对照。

**S6 双表与混音：FIR 中抽头写成 8。** 文档与标准二项式都是 `(1,4,6,4,1)/16`，实现取 8 后直流增益变成 18/16、1 kHz 处抬升约 1 dB、阶跃有 6% 过冲，并让本不削波的信号削波（29127 → 32767）；交付版自检只测已削波的满幅输入所以漏检。现修正为 6，并把插值（含 511→0 接缝与取整平局分数）、1024+256 个混合点、510 个混音样本（VOLUME_SHIFT 0/1/2 × FIR 旁路/启用）、32 个 FIR 小样本全部改为逐值对照，补记 FIR 群延迟 2 帧与 1k/5k/10k/15k/20k 频响。

## 验证

- `sim/run_simulation.ps1` 队列 12→14 台，提交后工作树与“干净克隆该分支”各跑一次，均为 14 台通过、退出码 0、“全部测试台通过，允许烧录”。
- 两张波表用 `tools/generate_wavetables.py` 重新生成后 SHA-256 与交付说明记录一致；新增的 `.gitattributes`（`*.hex text eol=lf`）保证二次签出后仍是 LF，记录值才成立。
- 故障注入对照：18 拍帧、逻辑右移、错误取整、中抽头 8 四种改法都按预期失败（日志在 `docs/evidence/*-review-20261015/logs/`）。

## 证据与产物位置

`docs/evidence/s4-review-20261015`、`s5-review-20261015`、`s6-review-20261015`（复核记录、日志、交付版基线、向量元数据）、`docs/evidence/s4-s6-review-20261015`（提交后与克隆门禁日志）、`docs/evidence/teammate-simulation`、`docs/evidence/s4-mcp3208.md`/`s5-pressure-bend.md`/`s6-audio.md`（交付说明更新）、`output/handoff_milestone2_20261008/source/sim/vectors/`、`tools/generate_wavetables.py`、`tools/s6_reference.py`、`tools/render_mcp3208_waveform.py`。

本地归档 `archive/FPGA-20261015-v0.8/v0.9/v0.10` 按仓库 `.gitignore` 未入库（v0.8 内含 740 KB 厂商数据手册原件）；复核记录里已把其中的基线、日志与校验值一并交入 git。

## 复现

```powershell
$env:PATH = 'D:\NanjingUniversity\FPGA\msys64\ucrt64\bin;' + $env:PATH
Set-Location output/handoff_milestone2_20261008/source
pwsh -NoProfile -File sim/run_simulation.ps1 `
  -Iverilog D:\NanjingUniversity\FPGA\msys64\ucrt64\bin\iverilog.exe `
  -Vvp D:\NanjingUniversity\FPGA\msys64\ucrt64\bin\vvp.exe
```

## PR 基线说明

基线选 `fix/m2-build-issues` 是因为它是本分支的直接父提交；`origin/main` 当前为 `b559237`（v1.01 发布），并不包含 `3a31eb2`，所以以 main 为基线会把上一批 milestone-2 构建改动一并纳入。若确实要合入 main，建议先把 `3a31eb2` 合入 main，或把本 PR 改成 stacked 形式。