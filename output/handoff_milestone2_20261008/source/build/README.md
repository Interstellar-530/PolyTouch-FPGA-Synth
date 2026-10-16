# 构建与 SRAM 烧录

在本目录运行脚本。两档由 profiles.tsv 绑定封装、约束与输出目录，共用 sources.list，已包含 S4–S6 模块。默认 debug 对应板载 PT8211；standard 对应外置 PCM5102A 和 12.288 MHz 时钟。

```powershell
.\build.ps1 -Profile debug
.\build.ps1 -Profile standard
```

工具自动从 C/D/E 盘顶层 Gowin 目录查找，也可指定 -GwSh、-Programmer 或设置 GOWIN_GW_SH、GOWIN_PROGRAMMER。

每次构建新建工程，避免旧 GPRJ 漏掉源文件。两档输出分别为 gowin_top_integrated/runs/<本次编号>/instrument/impl/pnr/instrument.fs 和 gowin_top_i2s_std/runs/<本次编号>/instrument/impl/pnr/instrument.fs。报告也保留在本次工程目录。成功后写入 receipts/debug.json 或 receipts/standard.json，记录输出路径及输入文件大小、修改时间；失败会清除该档的成功记录。工程目录属于保留的构建产物，不会自动删除。

硬件接线核查后，构建和烧录必须选择相同档位：

```powershell
.\program_sram.ps1 -Profile standard
# 板载 PT8211 调试使用：
.\program_sram.ps1 -Profile debug
```

烧录默认先执行全部 RTL 仿真门禁。通过后，只读取所选档位的成功记录；源文件或位流变化时要求重建。不会自动选旧 source/impl/pnr/instrument.fs 或交接包 artifacts/instrument.fs。时间和大小用于防止日常误用旧产物，不是内容的密码学证明。

需要有意使用历史版本时，显式传入 -FsFile，并核对其接线档位；该用法仍执行仿真门禁：

```powershell
.\scan_jtag.ps1
.\program_sram.ps1 -FsFile '<明确选择的位流路径>' -Cable '<当前扫描的线缆名称>'
```

器件默认 GW2A-18C，操作码 2 表示 SRAM Program，断电失效。-SkipSimulation 只用于仿真器不可用的极端情况，并须在调试日志说明原因。

旧 Tcl 入口 build_instrument.tcl、build_top_integrated.tcl、build_top_i2s_std.tcl 已转发到共用逻辑。直接调用 Tcl 不生成 PowerShell 成功记录；自动选择位流时请使用 build.ps1。

本项验证在仓库根目录运行 tools/verify_build_profiles.py。它实际调用 Gowin 创建工程、加入源文件并设置封装，只替换 run 以停止在综合前，再用 Icarus 编译两档。构建与烧录选择测试使用隔离目录和模拟工具，不接触 JTAG。证据见 docs/evidence/FPGA-构建入口-20261016-v0.1。

2026-10-16 实际综合修正：Gowin 将 impl 输出写到当前工作目录。公共 Tcl 现在先进入本次工程目录，并复制所需的 Verilog 头文件，再执行构建。已通过真实综合确认输出落在本次工程的 impl/gwsynthesis 下；本轮未执行 PnR。该修正包含在第三项音色控制提交中。
