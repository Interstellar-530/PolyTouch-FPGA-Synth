# PolyTouch FPGA Synth — v2.1.0

2026-10-21 新版整合六项优化与审核修正：力度边界、构建哈希绑定、HID 音色/音量控制、事件预取、钢琴/吉他少表复用，以及独立 32 声部音色原型。当前开发分支为 `codex/s4-s6-pressure`，源码入口仍是 `output/handoff_milestone2_20261008/source`。生产版维持 8 声部；32 声部原型已接入少表音色，实际计算时钟由后续晶振提供。详见 [v2.1.0 说明](docs/releases/v2.1.0.md) 与 [发布前补审](docs/reviews/FPGA-发布前集成补审-20261021-v0.1.md)。

## 当前代码与验证范围

正式源码只维护一份：`output/handoff_milestone2_20261008/source`。目录日期是历史交接包名称，不能据此判断版本；`archive/`、`tmp/`、独立硬件实验和生成的工程不是生产源码入口。

当前已使用的是 `debug8`：板载 27MHz、46.875kHz、PT8211 耳机输出，8 个独立声部，可经 UART/电脑界面切换电钢琴和吉他。支持 `I0/I1`、`V0..V100`、`D0/D1`、音符按下/松开与清音；音频由 FPGA 实时生成。主音量 100 为本路径原始电平，50 约 −12dB，0 静音。

`standard27` 是实体组装的正式入口：27MHz、46.875kHz、24 位标准 I2S 到 PCM5102A，CH9350L 直接接 USB 键盘，MCP3208 接 FSR/弯音。当前外设尚未整机接通；CH9350L 链路的 F6（钢琴/吉他切换）和 ↑/↓ 音量已在 RTL 与顶层仿真中补齐，实体键盘尚未实测；RGB 灯、彩屏、合唱和 32 声部板级集成仍是工作安排中的待办，不应按计划写成已实现。

`debug8usb` 最近一次构建（2026-10-22，优化 07 后）为 Logic 11378、寄存器 3702、**BSRAM 25/46**；DSP 为 1.75/24，包括 1×MULT18X18、1×MULT9X9 和 1×MULTALU36X18。27MHz 约束下 Fmax 35.885MHz，最差 setup +9.171ns、hold +0.319ns，报告中负裕量端点均为零。`standard27` 同轮完成 PnR：Logic 11406、寄存器 3674、BSRAM 25/46、Fmax 38.557MHz、setup +11.102ns、hold +0.211ns。钢琴表由 36 张近似复用为 12 张，最差单表误差约 −60.7dB，相对音频数据并非无损；吉他由 36 张逐位复用为 30 张。主要谐波与实际 RTL 输出差异的审核见 [第五项报告](docs/reviews/FPGA-波表复用音质审核-20261021-v0.1.md)，尚未做人耳盲听确认。F6 持键重复报告与键位重排不会再次切换，松开后重新允许触发。位流 SHA256：`792722DED0EEAADC3F8D288FBF848E31B86BDA438E17A2A9BD874DFBB29367D2`。这是本轮生成、尚未烧录的 PT8211 调试位流；`standard27` 同轮已完成综合与 PnR。历史已烧录版见烧录日志。
CH9350L 超时策略在优化 07 后默认为 `idle-only`：无持键时 2 秒静默可清音，持键期间不因静默超时截断长音，收到 0x86 拔出通知仍立即清音。需要旧行为时可在顶层设置 `HOST_KBD_TIMEOUT_POLICY=0`；实体长按和真实拔线帧验收仍未完成。

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

第六项独立 `ram32_top` 及后续钢琴/吉他集成已补审修正：32 声部事件、ADSR、少表音色、24 位 I2S 通过定向验证，实测帧尾 992/1024 拍。BSRAM 26/46、2 个 MULT18X18，49.152MHz 约束下 Fmax 49.302MHz、setup +0.062ns。旧 RAM 接口保留兼容，音色扩展使用独立原型模块。晶振后续到位；板级引脚与实物音频仍待集成，生产版本维持 8 声部。此次不追加完整长门禁或烧录，详见[集成补审](docs/reviews/FPGA-发布前集成补审-20261021-v0.1.md)。

## 历史版本

[v2.0.1 候选版](docs/releases/v2.0.1.md)、[v2.0.0](docs/releases/v2.0.0.md)、[v1.01](docs/releases/v1.01.md)、[v1.0.0](docs/releases/v1.0.0.md) 和 [源码导读](docs/releases/v1.0.0-code-guide.md) 保留各版基线。v2.0.1 是本日早期候选记录，其内容纳入 v2.1.0；v2.0.0 是 USB 键盘调试档与 8 声部音频的合流，v1.01/v1.0.0 是四声部基线。历史 `0x5633` 是旧位流 User Code，不代表当前板内一定仍运行该版本。旧版资料及文件地图见 [版本索引](docs/版本索引与文件地图-20261014-v0.1.md)。
