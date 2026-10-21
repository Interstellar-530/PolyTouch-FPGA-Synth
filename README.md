# PolyTouch FPGA Synth — v2.0.0

当前工作入口是 `codex/s4-s6-pressure`。2026-10-21 的 v2.0.0 把 `codex/guitar-preview-ddr3-20261020` 的最新推送（`33d29af`、`754fc08`、`1fd865a`）并入本线：新增 `debug8usb`（CH9350L USB 键盘 + FSR 压力的 27 MHz 标准 I2S 调试档）、精确静音收敛、亮音色库表序修正，并保留本线的 8 声部电钢琴/吉他、键控响度、主音量与 24 位公共低通。增量、取舍与验证边界见 [v2.0.0 发布说明](docs/releases/v2.0.0.md)。

## 当前代码与验证范围

正式源码只维护一份：`output/handoff_milestone2_20261008/source`。目录日期是历史交接包名称，不能据此判断版本；`archive/`、`tmp/`、独立硬件实验和生成的工程不是生产源码入口。

当前已使用的是 `debug8`：板载 27MHz、46.875kHz、PT8211 耳机输出，8 个独立声部，可经 UART/电脑界面切换电钢琴和吉他。支持 `I0/I1`、`V0..V100`、`D0/D1`、音符按下/松开与清音；音频由 FPGA 实时生成。主音量 100 为本路径原始电平，50 约 −12dB，0 静音。

`standard27` 是实体组装的正式入口：27MHz、46.875kHz、24 位标准 I2S 到 PCM5102A，CH9350L 直接接 USB 键盘，MCP3208 接 FSR/弯音。当前外设尚未整机接通；CH9350L 的 F6/音量控制、RGB 灯、彩屏、合唱和 32 声部是工作安排中的待办，不应按计划写成已实现。

最新已烧录调试版记录为 Logic 10778、寄存器 3398、BSRAM 40/46、1×MULT18X18＋1×MULT9X9；27MHz 约束下 Fmax 31.386MHz、setup/hold 违规为零。位流 SHA256：`2F8DB574A2ECABE2E71A8B6A8DA32CDAF2EF993F9198AB120CAA15B35DFC8606`。这些是对应历史构建的结果，不是新增外设配置的实测指标。

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

本轮按用户要求使用与改动相关的短检查，记录在同步证据目录；没有宣称全量门禁通过。`run_simulation.ps1` 与烧录脚本的历史默认仍是全量门禁，精简入口安排见软件计划。已知完整套件曾停在 GPIO/演示切换路径；实物长音、模拟输出、延迟和冷启动仍按实际验收记录报告。

64 路计算/PLL 原型和 DDR3 实验均保留各自入口，不能直接替代完整 32/64 声部乐器。修改声部、效果、显示前重新核算 BSRAM、乘法器和每帧周期；32 声部不能只改顶层参数。

## 历史版本

[v2.0.0](docs/releases/v2.0.0.md)、[v1.01](docs/releases/v1.01.md)、[v1.0.0](docs/releases/v1.0.0.md) 和 [源码导读](docs/releases/v1.0.0-code-guide.md) 依次保留发布基线：v2.0.0 是 USB 键盘调试档与 8 声部音频的合流，v1.01/v1.0.0 仍是四声部基线。历史 `0x5633` 是旧位流 User Code，不代表当前板内一定仍运行该版本。旧版资料及文件地图见 [版本索引](docs/版本索引与文件地图-20261014-v0.1.md)。
