# 第二项：统一构建入口与烧录位流选择

2026-10-16，在第一项压力音量提交 c231c19 基础上完成。旧 build.ps1 未加入 S4–S6 四个必要模块，烧录脚本的默认搜索位置也不对应新工程，可能误选历史位流。本项修改构建和烧录脚本、清单、说明及复现工具，没有修改 RTL、引脚、音频参数和协议。

两档共用 sources.list 和 profiles.tsv，分别绑定调试封装及 Dock 约束、标准 I2S 封装及外置时钟约束。每次创建独立工程，避免旧 GPRJ 的文件列表滞后。构建成功且产生非空位流后，记录档位、封装、输出路径及输入文件时间和大小；若构建期间输入变化则拒绝登记。默认烧录只选对应档位成功记录中的文件，源码变化或构建失败后需要重建。显式 -FsFile 继续支持选择历史产物。全量仿真门禁保持不变，未通过不会调用烧录工具。

tools/verify_build_profiles.py 的 13 项检查全部通过，见 results.json。真实 Gowin 1.9.11.03 创建了 debug、standard 工程并加入完整文件、设置封装；实际路径确认是 <本次目录>/instrument/instrument.gprj，位流期望位置是其 impl/pnr/instrument.fs。Icarus 对两档真实源清单分别完成 RTL 编译。测试以替换 Gowin run 命令的方式停止在综合前；构建登记与烧录选择在独立模拟工程中验证，不产生可烧录位流。

检查覆盖两档成功构建后的选择、源码变化拒绝、失败构建清除成功记录、拒绝旧目录回退、显式历史文件选择及失败的仿真门禁阻止烧录。门禁使用模拟返回值验证分支，没有执行完整门禁，也没有调用真实 programmer。

补跑两项音频定向仿真均通过：tb_pressure_gain 检查 4096 个 ADC 码、4797 帧，增益范围 1024–4096、每帧最大变化 32，满范围需要 96 帧；tb_shared_engine 检查 16 组，分量求和逐位一致，全局交叉淡化误差不超过 2 LSB。日志在 rtl-smoke/。本项没有重新综合、布局布线或上板，资源和时序仍需后续真实构建确认。

仓库根目录复现：

```powershell
& 'C:\Users\ROG\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' tools/verify_build_profiles.py
& 'C:\Users\ROG\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' tools/run_pressure_verification.py --only tb_shared_engine tb_pressure_gain --out docs/evidence/FPGA-构建入口-20261016-v0.1/rtl-smoke
```

先参考了 [Sipeed 官方开源示例](https://github.com/sipeed/TangPrimer-20K-example)，现有本机脚本适合小幅修复，因此未引入外部代码和新依赖。归档为 archive/FPGA-20261016-v0.3。单独 revert 本项提交可回退，保留第一项压力音量；旧构建和位流选择缺陷也会恢复。

额度从本会话实时 token_count.rate_limits 读取，应用额度接口返回 Invalid app tool request。执行中两个窗口均未触及剩余 15% 暂停阈值，结束时另存额度快照。该监控依赖当前会话最近记录，不是后台独立监控。

本项临时工程在 tmp/build-profiles-verification-20261016，仿真编译目录在 tmp/pressure-verification-20261016；结束前按明确路径列出、核对后删除。保留源文件、复现脚本、测试证据及归档。下一项等待用户继续指令。
