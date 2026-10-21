# PolyTouch FPGA Synth — v2.0.1 本地候选版

当前工作入口是 `codex/s4-s6-pressure`。2026-10-21 已重新获取 GitHub 远端：`main` 与本地基线均为 `2d3db6c`，USB 键盘分支的最新推送已经包含在 v2.0.0 中。v2.0.1 本地候选版保留这次合流的 8 声部双音色、键控响度、24 位主链路和精确静音，恢复缺失测试台即拒绝通过的规则，并将五个已有的 8 声部/吉他测试纳入门禁。`debug8usb` 实际使用板载 PT8211；PCM5102A 使用 `standard27`。本轮结果见 [v2.0.1 说明](docs/releases/v2.0.1.md) 和 [Git 差异与优化方向](docs/reviews/FPGA-Git差异与优化方向-20261021-v0.1.md)。

## 当前代码与验证范围

正式源码只维护一份：`output/handoff_milestone2_20261008/source`。目录日期是历史交接包名称，不能据此判断版本；`archive/`、`tmp/`、独立硬件实验和生成的工程不是生产源码入口。

当前已使用的是 `debug8`：板载 27MHz、46.875kHz、PT8211 耳机输出，8 个独立声部，可经 UART/电脑界面切换电钢琴和吉他。支持 `I0/I1`、`V0..V100`、`D0/D1`、音符按下/松开与清音；音频由 FPGA 实时生成。主音量 100 为本路径原始电平，50 约 −12dB，0 静音。

`standard27` 是实体组装的正式入口：27MHz、46.875kHz、24 位标准 I2S 到 PCM5102A，CH9350L 直接接 USB 键盘，MCP3208 接 FSR/弯音。当前外设尚未整机接通；CH9350L 链路的 F6（钢琴/吉他切换）和 ↑/↓ 音量已在 RTL 与顶层仿真中补齐，实体键盘尚未实测；RGB 灯、彩屏、合唱和 32 声部仍是工作安排中的待办，不应按计划写成已实现。

`debug8usb` 最近一次构建（2026-10-21，波表复用后）为 Logic 11392、寄存器 3702、**BSRAM 25/46**；DSP 包括 1×MULT18X18、1×MULT9X9 和 1×MULTALU36X18。27MHz 约束下 Fmax 37.890MHz，最差 setup +10.645ns、hold +0.208ns，报告中负裕量端点均为零。钢琴表由 36 张复用为 12 张、吉他由 36 张复用为 30 张，试听对比的最差差分为 −60.7 dB。F6 持键重复报告与键位重排不会再次切换，松开后重新允许触发。位流 SHA256：`1D3A8849F67BD2BD25FF7F9A9DE4ED00E5C52AAB141D9F60B9FE932FAE7ABC5D`。这是本轮生成、尚未烧录的 PT8211 调试位流；`standard27` 本轮只做编译展开，未重做 PnR。历史已烧录版见烧录日志。

## 本周直接阅读

| 入口 | 内容 |
|---|---|
| [周末硬件清单与安装说明](docs/hardware/FPGA-周末硬件组装清单与安装说明-20261020-v0.1.md) | 10/24—25 装配、元件、约 100 元视觉配件预算、引脚、电源与操作 |
| [周末前软件安排](docs/planning/FPGA-周末前软件工作安排-20261020-v0.1.md) | 两人四天分工、32 声部冲刺、效果/灯屏、AI 和计算资源安排 |
| [工作区同步证据](docs/evidence/FPGA-工作区同步-20261020-v0.1/README.md) | 源码副本遍历、来源选择、构建绑定与本轮短检查 |
| [最新烧录记录](docs/logs/FPGA_FLASH_20261020.md) | 10/20 连续改进及对应位流、资源与烧录边界 |
| [电脑演奏界面](tools/serial_keyboard/README.md) | 当前串口操作、自检和键位 |
| [吉他预览](docs/evidence/FPGA-吉他音色预览-20261020-v0.1/README.md) | 离线试听、真实采样比较及生成脚本，属于研究资料 |
| [DDR3 独立实验](docs/evidence/FPGA-DDR3冒烟-20261020-v0.1/README.md) | 独立测试顶层与已有证据，未集成到乐器音频路径 |

## 复现与协作

在仓库根目录构建当前调试档或正式档：

```powershell
& '.\output\handoff_milestone2_20261008\source\build\build.ps1' -Profile debug8
& '.\output\handoff_milestone2_20261008\source\build\build.ps1' -Profile debug8usb
& '.\output\handoff_milestone2_20261008\source\build\build.ps1' -Profile standard27
```

本机需 Gowin EDA 与 Icarus Verilog。当前生成 ROM 和 HEX 已入库，普通构建不必重新下载音色素材；音色再生成脚本仍可能依赖本地样本目录，其路径见脚本和来源说明。不要将 `tools/agent-runtime/`、语言环境或编译缓存加入 Git。

本轮按用户要求停止完整长门禁，完成 9 个原始定向测试、1 个保留原断言的短窗口音色切换测试、两档编译展开、缺失测试台拒绝通过负例和 ROM 重建检查，记录在 [合流复核证据](docs/evidence/FPGA-合流复核-20261021-v0.1/README.md)。没有完整门禁通过或烧录许可。`run_simulation.ps1` 与烧录脚本仍默认执行完整门禁；实物长音、模拟输出、延迟和冷启动仍待实际验收。

64 路计算/PLL 原型和 DDR3 实验均保留各自入口，不能直接替代完整 32/64 声部乐器。修改声部、效果、显示前重新核算 BSRAM、乘法器和每帧周期；32 声部不能只改顶层参数。

## 历史版本

[v2.0.1 候选版](docs/releases/v2.0.1.md)、[v2.0.0](docs/releases/v2.0.0.md)、[v1.01](docs/releases/v1.01.md)、[v1.0.0](docs/releases/v1.0.0.md) 和 [源码导读](docs/releases/v1.0.0-code-guide.md) 保留各版基线。v2.0.1 尚未提交或打 Git 标签；v2.0.0 是 USB 键盘调试档与 8 声部音频的合流，v1.01/v1.0.0 是四声部基线。历史 `0x5633` 是旧位流 User Code，不代表当前板内一定仍运行该版本。旧版资料及文件地图见 [版本索引](docs/版本索引与文件地图-20261014-v0.1.md)。
