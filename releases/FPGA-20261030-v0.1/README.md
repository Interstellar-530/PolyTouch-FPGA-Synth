# 2026-10-30 工作结果

本包对应当前32声部HDMI乐器版本，包含当天的延音稳定修复、快速踏板判定、面板文字修复、算法图稿与实际写入Flash的位流。板内标识为User Code **0x00002626**、Status **0x00006020**。源码主入口仍为仓库的 `output/handoff_milestone2_20261008/source`；本包 `source/verified-inputs` 保留构建时的原始字节快照，供核对收据与复现。

踏板快速路径为原始压力 → 三点中值 → 512/256回差 → 按下2点/松开6点连续确认。原IIR继续提供平滑显示，不参与踏板状态等待；确认只在2kHz新样本更新时推进。默认IdleOnly键盘空闲超时保留延音，明确断开、Panic与Strict策略的清音保护保留。UI修复PEDAL DOWN、PRESSURE、VELOCITY、采样率及状态文字裁切，并显示实际USB键盘输入。

最终7项定向RTL自检和1项真实生产顶层测试通过，共8项。真实2kHz节拍的24组测试中，最长按下1.499998ms、松开3.499998ms；真实MCP3208模型与生产顶层也通过5ms内释放踏板状态的截止断言。2ms短掉压可保持，持续5ms低值会被判为松开。这是踏板状态更新范围，不能当作整机模拟音频延迟或ADSR余音结束的测量值。

Gowin V1.9.11.03 Education实现的Setup/Hold违例端点均为0；BSRAM31/46，MULT18X18为5，另有MULTALU36X18为1；54MHz计算域Fmax54.879MHz，最差setup余量0.297ns。SRAM下载、独立读码、Flash擦写和内置校验均完成。从Flash重载后的首次读码尚未就绪，等待稳定后确认标识匹配，原始过程记录全部保留。Flash现已持久更新。

`target/instrument.fs` 的SHA256为 `b4dd1b5d1a5d89ba871e34f4e230a85fbe3c92c486934f57dcc811bdb2edf003`。完整Quick/Full未重新通过；历史失败记录不转写成通过。实物冷启动、持续轻压、接线掉压和听感仍需现场确认。

## 图稿

| 文件（target目录，均有SVG与PNG） | 用途 |
|---|---|
| 01-overview-light / 01-overview-dark | 总览，适合报告与视频 |
| 02-signal-flow-detail | 事件、合成、输出与快速踏板路径 |
| 03-demo-construction | 曲谱编排、事件ROM、板上实时合成 |
| 04-sustain-stability | 中值、回差、连续确认、延音与清音保护 |

演示曲存储音高、力度、按下/松开、等待和循环等演奏事件，自动派发到与手动演奏相同的声部引擎。声音仍由FPGA逐声部、逐样本合成；音色波表提供单周期波形，曲目ROM不保存整曲预录音频。图稿不虚构FFT、混响、合唱或LED指引功能。竞赛条款核对见 `evidence/competition-check.md`。

## 复现与证据

依次阅读 [MANIFEST.md](MANIFEST.md)、[REPRODUCE.md](REPRODUCE.md) 和 [CHANGES.md](CHANGES.md)。`source/verify_release.py` 检查包内SHA256、成功构建输入的原始快照、8项通过证据与位流/Flash标识绑定，不重新运行仿真或访问开发板。

本包保留最终源文件、图稿、位流、关键日志与校验记录。旧版本完整原始归档仍位于本机 `archive/FPGA-20261030-v0.1` 至 `v0.8`，未整体上传；零散试听、旧位流、临时构建与运行时环境不属于本包。Git通过本目录的字节保留规则避免换行转换破坏收据及SHA256。
