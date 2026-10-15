# FPGA-20261015-v0.8 归档清单

## 内容

本次归档是 2026-10-15 对 S4 MCP3208 数字交付的独立复核与其后的修正，来源工作树为
`PolyTouch-FPGA-Synth-sim-main-55528`（分支 `fix/m2-build-issues`），交付目录为
`output/handoff_milestone2_20261008/source`。归档目录名沿用项目规则
`FPGA-日期-版本`，版本号按 S2 的 v0.4、S3 的 v0.7 顺延取 v0.8；若用户主工作区的
流水号不同，只需改目录名。

复核结论：交付版 `mcp3208_spi.v` 的读回窗口提前一拍且整帧只有 18 拍（DS21298E
要求 19 拍，第 7 拍为器件驱动的 null 位、第 8～19 拍为 B11..B0），在真实器件上
会把每个码值右移一位并丢掉 B0；交付版 `mcp3208_model.v` 与主机共享同一错误假设，
所以原自检必然通过。本轮按数据手册修正主机、模型与自检，并新增 I2S 并存台与
参数台，14 台门禁退出 0。详细判定与证据见 `evidence/README.md`。

## 目录

- `source/rtl/audio/mcp3208_spi.v`：修正后的 MCP3208 mode-0 主机（19 拍帧、第 8～19 拍采样、整帧最后一个下降沿提交、SPI_HZ<1 守护）。
- `source/sim/mcp3208_model.v`：按 DS21298E 重写的引脚级器件模型。
- `source/sim/tb_mcp3208_spi.v`：重写的 S4 自检，含线级审计、双通道、8 路互异码值、256 例固定种子随机值、busy 期间 start 忽略、帧内复位恢复、超时保护；波形转储改为 `+dump` 才写 VCD。
- `source/sim/tb_mcp3208_i2s_coexist.v`、`source/sim/tb_mcp3208_params.v`：新增的并存台与参数台。
- `source/sim/run_simulation.ps1`：门禁脚本，队列 12→14 台。
- `source/tools/render_mcp3208_waveform.py`：从 VCD 渲染单帧波形并自检帧长、DIN 命令位与 MISO 译码。
- `evidence/README.md`：复核记录（结论、依据、证据、修改、覆盖对照、风险、复现命令）。
- `evidence/datasheet-excerpt.txt`：Microchip MCP3204/3208 数据手册 DS21298E 关键段落与图注摘录。
- `evidence/MCP3204-3208-datasheet.pdf`：数据手册原件（2026-10-15 自 Microchip 官网下载）。
- `evidence/baseline/`：交付版三件文件的原样副本（复核基线）。
- `evidence/logs/`：修正前失败摘录与修正后三台测试日志。
- `evidence/mcp3208-frame-20261015.png`：从 `+dump` 波形渲染的第 11 次事务（CH0=1374），标注 19 拍编号、DIN 命令位与 DOUT 的 null/B11..B0 位置。
- `evidence/gate-20261015.log`：14 台门禁完整输出。
- `FPGA-缺件期间仿真与算法任务-20261014-v0.2-S4复核后.md`：任务清单在本次复核后的副本（S4 行已划去并写明复核结论）。

## 复现命令

```powershell
$env:PATH = 'D:\NanjingUniversity\FPGA\msys64\ucrt64\bin;' + $env:PATH
Set-Location output/handoff_milestone2_20261008/source
pwsh -NoProfile -File sim/run_simulation.ps1 `
  -Iverilog D:\NanjingUniversity\FPGA\msys64\ucrt64\bin\iverilog.exe `
  -Vvp D:\NanjingUniversity\FPGA\msys64\ucrt64\bin\vvp.exe
```

复核交付版错位时，用 `evidence/baseline/mcp3208_spi.v` 覆盖
`rtl/audio/mcp3208_spi.v` 后重跑 `tb_mcp3208_spi`，会得到退出码 1 与
“frame used 18 SCLK edges … expected 19”、以及形如 `value=3800` 读回 `1900`
的减半结果。

## 回退

三件交付物均可用 `evidence/baseline/` 中的同名文件覆盖回交付版；新增的两台测试
从 `run_simulation.ps1` 队列中删除即可同时移除。

## 限制

归档只声明 RTL/模型层面的 PASS。ADC 实物供电、参考电压、引脚 Bank 电平、噪声与
FSR 机械特性仍须到货后逐件验收；`tCSH >= 500 ns` 的请求间隔与 `start` 在 busy
期间不排队这两条约束需要顶层调度配合，详见 `evidence/README.md` 的风险一节。