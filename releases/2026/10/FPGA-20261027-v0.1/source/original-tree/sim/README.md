# 仿真门禁

按2026-10-23要求，默认使用Quick短门禁，完整历史测试保留为Full。运行本目录的run_simulation.ps1，失败返回非零；不使用SkipSimulation代替短门禁。

| 入口 | 范围 |
|---|---|
| 不带参数，或 `-Suite Quick` | 14项生产路径检查（含FSR消音与F8暂停/继续）与6个I2S参数负例 |
| `-Suite Host` | 键位链路、长按策略、顶层控制及F8暂停/继续四项 |
| `-Suite Ram32` | 调度器、音色ROM、旧32声部原型、控制前级及73.728MHz完整音频引擎，共5项 |
| `-Tests tb_adsr,tb_event_fifo` | 指定已有名称，未知名称、空清单或缺失测试拒绝通过；PowerShell调用使用数组，命令行-File仅单项最可靠 |
| `-Suite Full` | 当前79项正向测试与6个参数负例，保留历史兼容、长音频捕获及32/64路实验；用 `-ListTests` 查看当前清单 |
| `-ListTests` | 只列所选清单，不编译、不生成运行目录 |

Quick覆盖采样节拍、ADSR、事件队列、两时钟档16/24位I2S、ADC帧、压力/弯音、压力增益、力度边界、宽主混音及HID顶层操作。完整音频捕获、旧GPIO路径、大量历史等价性/音色扫描和32/64路原型不再随每次开发或烧录自动运行。修改这些功能时通过-Tests或对应专项补查；公共音频算法、时钟、ROM内容或旧输入路线变化需要相应专项验证，Quick不能证明其全部正确。

短门禁把tb_host_kbd_timeout的LONG_HOLD_MS设为100，仍超过20ms测试watchdog的三个窗口，保留所有断言；Full保持默认5000ms。只改测试等待参数，不改生产2秒超时。Quick/Host/定向测试首个失败即结束，Full继续收集全部失败。每次新建独立运行目录，默认在仓库tmp/gate-模式-时间下；可显式指定BuildDir、MetricsDir、AudioCaptureDir。

每项编译限60秒、仿真默认限180秒，仿真上限可用-TimeoutSeconds调整。超时返回124并使门禁失败；不把无限等待当作通过。vvp使用-N，使$stop同样返回失败，参数负例另外检查退出码、FATAL及具体原因。参数与plusargs按Icarus[编译选项](https://steveicarus.github.io/iverilog/usage/command_line_flags.html)、[运行选项](https://steveicarus.github.io/iverilog/usage/vvp_flags.html)配置。

MetricsDir保留逐项编译/运行日志、耗时、真实退出码及gate-result.json。结果列出所选和未选项、输入SHA256及是否为完整回归；运行中输入变化会使结果作废。不要将Quick的通过写成Full通过，不复用旧PASS缓存。门禁脚本通过不代表位流、板级时序或模拟硬件已验收。

从仓库根运行：

```powershell
$gate = '.\output\handoff_milestone2_20261008\source\sim\run_simulation.ps1'
& $gate
& $gate -Suite Host
& $gate -Tests @('tb_adsr','tb_event_fifo')
& $gate -Suite Full -ListTests
```

program_sram.ps1默认先跑Quick，选择完整门禁用-SimulationSuite Full。烧录所需的构建输入和位流哈希验证保留。tools/run_audio_verification.ps1明确选择Full，仍执行完整音频验收。极端情况下的-SkipSimulation规则保留。

本机沙箱内Icarus可能异常退出；正常本机环境已验证短门禁。非零编译退出码始终视为失败。完整回归耗时较长，按需运行，不是新日常默认。
