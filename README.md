# PolyTouch FPGA Synth

高云 GW2A-18 / Sipeed Tang Primer 20K Dock 3714 电子乐器项目。当前源码在 [`source/`](source/)，历史版本按日期保存，入口为[版本时间线](docs/history/VERSIONS.md)。

当前功能基线为 **2026-10-30 最终交付**，原标签 `final-20261030`，实现提交 `ede17ff`、冻结提交 `efd76ea`。该版为 32 声部 HDMI 乐器，音频由 FPGA 实时合成。原始交付包、位流与验证范围见[最终交付说明](releases/2026/10/FPGA-20261030-v0.1/original-delivery/README.md)。归档编号 v0.N 只表示同日保存顺序，原语义版本与标签保持不变。

| 需要的内容 | 入口 |
|---|---|
| 当前 RTL、测试、约束与构建 | [`source/`](source/README.md) |
| 各日期版本与阶段源码 | [版本时间线](docs/history/VERSIONS.md) |
| 项目规划、设计和比赛资料 | [文档目录](docs/README.md) |
| 接线、采购和硬件搭建 | [`docs/hardware/`](docs/hardware/) |
| 仿真、构建和烧录原始证据 | [`evidence/`](evidence/README.md) |
| 独立实验与未合并候选 | [`experiments/`](experiments/README.md) |
| 演示图稿、试听与素材 | [`media/`](media/README.md) |
| 迁移映射与本次验证 | [目录整理记录](evidence/2026/11/FPGA-20261101-reorganization-v0.1/README.md) |

在仓库根目录运行：

```powershell
& './source/sim/run_simulation.ps1' -Suite Quick
& './source/build/build.ps1' -Profile hdmi
```

本机需要 Gowin EDA 与 Icarus Verilog；其他硬件配置和参数见 [`source/build/README.md`](source/build/README.md)。普通构建使用入库的 ROM/HEX；重新生成音色可能需要原样本和额外依赖。烧录应使用新路径生成的构建收据，并执行仿真门禁，不能直接复用旧绝对路径收据。

2026-11-01 的修改是目录和版本归档整理，未改 RTL 功能，也未烧录。原交付中的仿真、时序和 Flash 结果仍是当时的记录，实物冷启动与听感等未完成项目不因此变为已通过。完整历史首页保存在[迁移前 README](docs/history/README-before-20261101.md)。
