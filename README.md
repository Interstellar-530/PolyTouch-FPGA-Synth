# PolyTouch FPGA Synth — v2.1.1 本地合流基线

2026-10-30：32声部HDMI版本已更新到 **Flash**，User Code **0x00002626**，Status **0x00006020**。修复键盘IdleOnly空闲误清延音，FSR改为三点中值、回差和按下2点/松开6点确认，24组测试最长按下约1.5ms、松开约3.5ms；真实ADC生产顶层的5ms踏板状态断言通过。同步修复面板文字裁切并更新演示曲事件存储、板上实时合成与踏板稳定流程图。8项定向RTL自检、零setup/hold违例实现、Flash写入校验及重载标识核对通过；完整Quick/Full和实物冷启动未新增通过结论。今日源码、位流、图稿、证据与复现见[每日发布包](releases/FPGA-20261030-v0.1/README.md)，[Flash记录](docs/logs/FPGA_FLASH_FAST_PEDAL_20261030.md)。以下日期较早的记录保留为历史。

2026-10-26 F7/F8 新版已写入 **Flash**：使用已推送的 b656b0d / standard27 / IdleOnly，User Code **0x0000C452**。按用户要求跳过本轮仿真门禁；构建零时序违例，Flash 写入校验和从 Flash 重载标识核对通过。其他未提交曲目修改未纳入；实体按键、声音及彻底断电冷启动待现场确认。详见[新版烧录记录](docs/logs/FPGA_FLASH_F7F8_20261026.md)，归档 archive/FPGA-20261026-v0.6。

2026-10-26 新增 USB 键盘 **F8** 暂停/继续演示曲，保留当前位置；F7 切换手动/自动并在进入自动时从头播放。按用户要求只做一项简短自检，通过；未运行复杂门禁，未重建或烧录。说明见[演示曲暂停与播放](docs/releases/FPGA-演示曲暂停播放-20261026-v0.1.md)。

2026-10-26 新增 USB 键盘 **F7** 切换手动/自动演奏：自动模式按 F7 停曲进入手动，再按从头自动播放；重复上报和长按只切一次，同帧音符会清除。原音符键接管自动、F6 音色、音量和 UART D0/D1 保留。代码与自检说明见[F7 模式切换](docs/releases/FPGA-键盘演奏模式切换-20261026-v0.1.md)。本轮未重建或烧录，板上 Flash 暂不含 F7。

2026-10-26 CH9350L 代码核对通过：standard27 的 UART、state 2 报告、双排键位、长按策略、F6 和音量控制均已接入；本轮 Host 3 项、Quick 19 项、曲目 2 项通过（Host 已包含在 Quick 内）。实物模块及键盘兼容待验收，持键无通知断电仍可能需要 Esc/S3 清音。当前源码另有三处曲目修改，未为其重建或改写 Flash。详见[CH9350L 核对记录](docs/reviews/FPGA-CH9350L代码核对-20261026-v0.1.md)。

2026-10-26 周末版本已写入外部 Flash：复用 10/24 最终 `standard27 / IdleOnly`（CH9350L、外接 PCM5102A、FSR 按住消音），未改 RTL。按用户本轮明确要求跳过仿真门禁；操作 37 擦写校验成功，从 Flash 重载后读到 User Code `0x000063DC`、Status `0x00006020`。彻底断电冷启动与键盘实物验收待现场确认。详见[Flash 记录](docs/logs/FPGA_FLASH_20261026.md)，归档 `archive/FPGA-20261026-v0.1`。

2026-10-24 FSR 消音：FSR 已从连续音量控制改为“按住消音、松开恢复”，演示与串口演奏均有效，旋钮仍控制弯音。新 standard27 已写入 SRAM，User Code `0x000063DC`；四项定向仿真、Quick 19 项和烧录后配置标识核对通过。此前用户已确认外接 DAC 能发声，本次 FSR 的实物力度阈值和听感待按压确认。详见[FSR 消音说明](docs/releases/FPGA-FSR消音-20261024-v0.1.md)。

2026-10-24 实物切换：开发板由 `debug8`（User Code `0x00003F62`）切换到 `standard27` SRAM 位流（`0x0000BF87`），保留 COM13 原串口演奏，启用 MCP3208 的 FSR/弯音与外接 PCM5102A。CH9350L 尚未到货，T7 外部晶振不接；Flash 未改写。Quick 18 项和曲目 2 项自检通过，串口 16 条命令全部回复 OK，模拟输出与 FSR/旋钮实物效果待现场验收。详见[烧录记录](docs/logs/FPGA_FLASH_20261024.md)。

2026-10-23：`standard27` 的键盘超时策略和外设时序约束已修正并形成独立可复现候选。默认 `IdleOnly`，旧行为改为显式 `Strict`；两套构建收据和位流分离，烧录前核对策略与生成包装器哈希。I2S/MCP3208 路径加入 20ns 实现上界并完成端到端预算验证。当前共享源码仍有其他任务并行修改，本候选不代表那些修改已经统一验收；统一审核后再决定是否发布或烧录。详见 [候选修正说明](docs/releases/FPGA-8声部候选修正-20261023-v0.1.md)。

2026-10-22 硬件文档核准：组装入口统一为[搭建指导 v0.2](docs/hardware/FPGA-硬件搭建指导-20261022-v0.2.md)和[采购准备 v0.2](docs/hardware/FPGA-硬件采买与搭建准备-20261022-v0.2.md)。主线是 CH9350L USB 键盘、FSR/MCP3208 与 PCM5102A，先用 standard27；单向模式模块 RXD 接地、FPGA N8 留空。长按修复仍在独立分支，32 声部与灯屏仍待板级集成。本次只修正文档，没有增加硬件验收结果。依据见[交叉核查报告](docs/reviews/FPGA-硬件搭建交叉核查-20261022-v0.1.md)。

2026-10-22：当前后续开发入口为 `codex/v2.1.1-integration-20261022`。已在 v2.1.0 上合入队友四个测试台的修正，保留钢琴 12 表/吉他 30 表和此前全部审核修正。五个定向回归通过，生产实现及已发布位流保持不变；此前代码已推送至同名远端分支。详见 [v2.1.1 基线说明](docs/releases/v2.1.1.md) 与 [双方关系和取舍](docs/reviews/FPGA-队友版本合流评审-20261022-v0.1.md)。

2026-10-21 新版整合六项优化与审核修正：力度边界、构建哈希绑定、HID 音色/音量控制、事件预取、钢琴/吉他少表复用，以及独立 32 声部音色原型。已发布版本所在分支为 `codex/s4-s6-pressure`，源码入口仍是 `output/handoff_milestone2_20261008/source`。生产版维持 8 声部；32 声部原型已接入少表音色，实际计算时钟由后续晶振提供。详见 [v2.1.0 说明](docs/releases/v2.1.0.md) 与 [发布前补审](docs/reviews/FPGA-发布前集成补审-20261021-v0.1.md)。

2026-10-23 32声部核心续修已完成：关闭Gowin编译错误和73.728MHz时序违例，新增完整波表引擎音频/精确静音/I2S延迟自检，旧8/32/64路RAM实验兼容通过。最终Fmax75.564MHz，BSRAM26/46；这是独立核心原型，正式32声部板级档与灯光仍待办。见[核心修复报告](docs/reviews/FPGA-32声部核心修复-20261023-v0.1.md)。

## 当前代码与验证范围

正式源码只维护一份：`output/handoff_milestone2_20261008/source`。目录日期是历史交接包名称，不能据此判断版本；`archive/`、`tmp/`、独立硬件实验和生成的工程不是生产源码入口。

此前使用的是 `debug8`：板载 27MHz、46.875kHz、PT8211 耳机输出，8 个独立声部。2026-10-24 已在 SRAM 切换到 `standard27`，保留 UART/电脑界面与 `I0/I1`、`V0..V100`、`D0/D1`、音符按下/松开与清音。音频由 FPGA 实时生成，主音量 50 约 −12dB，0 静音；断电或 S4 重配置会恢复此前的 Flash 版本。

HDMI 仪表盘档在电脑端新增 `F7` 显示切换：`R0` 选择电脑端 WinForms 仪表盘，`R1` 恢复板载 HDMI；电脑端用 `Q` 请求一次状态、波形、频带活动和相位图快照。电脑端显示只解码状态，音频仍由 FPGA 生成。兼容实现位于 `tools/serial_keyboard`，对应 FPGA 入口为 `build -Profile hdmi`。

`standard27` 是实体组装的正式入口：27MHz、46.875kHz、24 位标准 I2S 到 PCM5102A，CH9350L 直接接 USB 键盘，MCP3208 接 FSR/弯音。当前外设尚未整机接通；CH9350L 链路的 F6（钢琴/吉他切换）和 ↑/↓ 音量已在 RTL 与顶层仿真中补齐，实体键盘尚未实测；RGB 灯、彩屏、合唱和 32 声部板级集成仍是工作安排中的待办，不应按计划写成已实现。

`debug8usb` 最近一次构建（2026-10-21，波表复用后）为 Logic 11392、寄存器 3702、**BSRAM 25/46**；DSP 包括 1×MULT18X18、1×MULT9X9 和 1×MULTALU36X18。27MHz 约束下 Fmax 37.890MHz，最差 setup +10.645ns、hold +0.208ns，报告中负裕量端点均为零。钢琴表由 36 张近似复用为 12 张，最差单表误差约 −60.7dB，相对音频数据并非无损；吉他由 36 张逐位复用为 30 张。主要谐波与实际 RTL 输出差异的审核见 [第五项报告](docs/reviews/FPGA-波表复用音质审核-20261021-v0.1.md)，尚未做人耳盲听确认。F6 持键重复报告与键位重排不会再次切换，松开后重新允许触发。位流 SHA256：`1D3A8849F67BD2BD25FF7F9A9DE4ED00E5C52AAB141D9F60B9FE932FAE7ABC5D`。这是本轮生成、尚未烧录的 PT8211 调试位流；`standard27` 本轮只做编译展开，未重做 PnR。历史已烧录版见烧录日志。

## 本周直接阅读

| 入口 | 内容 |
|---|---|
| [现有硬件图解接线手册](output/pdf/FPGA-现有硬件图解接线方案-20261023-v0.1.pdf) | 依据用户Dock背面丝印和DAC照片；8声部主链路、无音箱调试、到货DIP-8晶振、逐模块验收 |
| [硬件搭建指导 v0.2](docs/hardware/FPGA-硬件搭建指导-20261022-v0.2.md) | 核准后的 USB 主路线、逐信号接线、档位和验收边界 |
| [采购准备 v0.2](docs/hardware/FPGA-硬件采买与搭建准备-20261022-v0.2.md) | 新订单记录、物料缺口、电源与视觉配件状态 |
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
# 复核旧的严格超时行为时显式使用：
& '.\output\handoff_milestone2_20261008\source\build\build.ps1' -Profile standard27 -HostTimeoutPolicy Strict
```

本机需 Gowin EDA 与 Icarus Verilog。当前生成 ROM 和 HEX 已入库，普通构建不必重新下载音色素材；音色再生成脚本仍可能依赖本地样本目录，其路径见脚本和来源说明。不要将 `tools/agent-runtime/`、语言环境或编译缓存加入 Git。

本轮按用户要求停止完整长门禁，完成 9 个原始定向测试、1 个保留原断言的短窗口音色切换测试、两档编译展开、缺失测试台拒绝通过负例和 ROM 重建检查，记录在 [合流复核证据](docs/evidence/FPGA-合流复核-20261021-v0.1/README.md)。没有完整门禁通过或烧录许可。2026-10-23 起，`run_simulation.ps1` 与烧录脚本默认执行 Quick 短门禁，完整回归用 `-Suite Full`（烧录入口用 `-SimulationSuite Full`），使用范围见 `source/sim/README.md`；实物长音、模拟输出、延迟和冷启动仍待实际验收。

64 路计算/PLL 原型和 DDR3 实验均保留各自入口，不能直接替代完整 32/64 声部乐器。修改声部、效果、显示前重新核算 BSRAM、乘法器和每帧周期；32 声部不能只改顶层参数。

第六项独立 `ram32_top` 及后续钢琴/吉他集成已补审修正：32 声部事件、ADSR、少表音色、24 位 I2S 通过定向验证，实测帧尾 992/1024 拍。BSRAM 26/46、2 个 MULT18X18，49.152MHz 约束下 Fmax 49.302MHz、setup +0.062ns。旧 RAM 接口保留兼容，音色扩展使用独立原型模块。晶振后续到位；板级引脚与实物音频仍待集成，生产版本维持 8 声部。此次不追加完整长门禁或烧录，详见[集成补审](docs/reviews/FPGA-发布前集成补审-20261021-v0.1.md)。

## 历史版本

[v2.0.1 候选版](docs/releases/v2.0.1.md)、[v2.0.0](docs/releases/v2.0.0.md)、[v1.01](docs/releases/v1.01.md)、[v1.0.0](docs/releases/v1.0.0.md) 和 [源码导读](docs/releases/v1.0.0-code-guide.md) 保留各版基线。v2.0.1 是本日早期候选记录，其内容纳入 v2.1.0；v2.0.0 是 USB 键盘调试档与 8 声部音频的合流，v1.01/v1.0.0 是四声部基线。历史 `0x5633` 是旧位流 User Code，不代表当前板内一定仍运行该版本。旧版资料及文件地图见 [版本索引](docs/版本索引与文件地图-20261014-v0.1.md)。
