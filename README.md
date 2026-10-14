# PolyTouch FPGA Synth — v1.01

v1.01 在 v1.0.0 四声部基线上加入 S1 真实音频捕获、PCM/WAV/FFT 验收及完整十项 RTL 门禁，并记录 Flash 持久化。生产逻辑和原位流保持一致，板内 User Code 仍为 **0x5633**，支持 D0/D1 与电脑按住/松开演奏。版本名称按用户指定保留为 `v1.01`；S2 GPIO 琴键与后续外设功能仍待执行。

工程继续位于 [output/handoff_milestone2_20261008/source](output/handoff_milestone2_20261008/source/)。目录中的日期是旧交接包名称，版本以 Git 标签和本页为准，不维护第二份生产 RTL。

已有四个独立相位/频率/ADSR 声部、一种 512 点正弦波表与插值（四声部各自实例化）、力度缩放/混音、演示事件 FIFO 背压、重按/窃取及演示/手动隔离。音频来自 FPGA HDL，通过板载 PT8211 右对齐格式输出，采样率 **46.875 kHz**。GPIO 琴键、压力 ADC、双音色、外部标准 I2S 和 32 声部仍待实现。

| 阅读入口 | 内容 |
| --- | --- |
| [v1.01 发布说明](docs/releases/v1.01.md) | S1 增量、Flash 固件、复现与验证边界 |
| [v1.0.0 基线说明](docs/releases/v1.0.0.md) | 既有功能、ASCII 协议、硬件限制和源码导读背景 |
| [源码导读](docs/releases/v1.0.0-code-guide.md) | 模块关系、状态/单拍控制、时钟/复位、定点与队列 |
| [验证记录](docs/releases/v1.0.0-validation.json) | 生产 RTL 词法一致性、仿真结果和原位流校验 |
| [固件位流](releases/v1.0.0/instrument_sram_0x5633.fs) | SRAM/外部 Flash 共用的原始 0x5633 配置文件 |
| [电脑演奏工具](tools/serial_keyboard/README.md) | 键盘映射、GUI 和端口使用 |
| [队友仿真配置提示词](docs/handoff/FPGA-队友仿真环境配置提示词-20261013-v0.1.md) | 无板卡电脑配置 Icarus/可选 GTKWave |
| [S1 音频验收入口](tools/audio_capture/README.md) | 真实 PT8211 引脚捕获、PCM/WAV、频率与独立松键分析 |
| [Flash 冷启动记录](docs/logs/FPGA_DEBUG_LOG_20261014_V1_FLASH.md) | 10/14 将同一 0x5633 位流写入 Flash，GAO-Bridge 校验及断电验收 |

## 运行基线

在仓库根目录执行以下 Windows PowerShell 命令，Icarus 安装路径可通过门禁的 -Iverilog/-Vvp 参数覆盖。v1.0.0 标签内是九台；10/14 工作区新增真实音频捕获，门禁为十台，全部通过才允许烧录。完整 S1 频谱验收还需运行上述音频验收入口。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '.\output\handoff_milestone2_20261008\source\sim\run_simulation.ps1'
if ($LASTEXITCODE -ne 0) { throw 'Simulation gate failed' }
```

板上加载相应 SRAM 固件后，以实际枚举的 COM 口运行电脑界面。先关闭其它占用该串口的窗口；默认示例为 COM13。按 A/W/S/E/D/F/T/G/Y/H/U/J/K 演奏 C4-C5，A/D/G 为三音和弦，H 为 A4，最多四声部。

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File '.\tools\serial_keyboard\keyboard.ps1' -Port COM13
```

UART 使用 115200、8N1、CR/LF 结尾，支持 N1-N127、O1-O127、X、D0/D1、M0/M1。D0 进入手动等待，D1 从头演示；X 降低全部 gate，包络仍按 Release 衰减，M0 直接将数字输出置零。

## 版本与复现

SRAM 配置掉电失效。10/13 发布时没有改写 Flash；10/14 已按用户要求把同一 v1.0.0 位流写入 Flash，经 GAO-Bridge 完整校验、重载读码与用户断电验收，冷启动为 0x5633。原 Flash 0xFCF0 已被替换。转运或换板后仍需核对实际配置，不能仅凭仓库版本推断板内程序。

源码 tag、历史 .fs 和本轮验证分别保存。原位流 SHA256 为 `2C7C7001DD3EABF24D2A4ABC2FC93BE1DD441D76812E248B3B84A235DBD22675`，历史已烧录/读码和串口证据见发布说明；新综合的字节、User Code 不保证相同。v1.0.0 是 Git 版本号，0x5633 是该历史位流的器件读码，两者不是同一编码体系。

构建依赖 Gowin V1.9.11.03 Education（历史已验收版本）或经复验的兼容安装，仿真依赖 Icarus Verilog。声部扩展前重算 BSRAM/DSP，任何 Verilog 改动先过 RTL 门禁。当前混音可能削波，模拟底噪、正式外设和端到端延迟另行验收；不将仿真 PASS 当作这些项目通过。
