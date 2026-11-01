# 第四项审核证据

结论：功能与时序效果通过，无需修改生产 RTL。新增短台和门禁登记，并直接更正原实现说明中的资源口径和瓶颈判断。

`simulation_results.json`、`tb_event_prefetch_compile.log`、`tb_event_prefetch_run.log` 是本轮有效检查，30 个预期事件按序递送，所有断言通过。测试为生产 `source/sim/tb_event_prefetch.v`，归档时保留对应快照；运行脚本 `commands/run_review.py` 使用现有 Icarus，仅运行此短台，未调用完整门禁。

`commands/collect_build.py` 只核对并收集已经成功的第四项构建，不调用综合器。`metrics_verified.json` 记录当前 222 个输入、输入摘要、位流和工具版本均匹配，前后输入差异只有 `top.v`。前后两次位流均保留在既有构建目录，内容与各自记录相符。`build_reports/` 与 `debug8usb.receipt.json` 对应第四项优化后的构建；原实现全部证据在相邻的 `FPGA-优化04-仲裁路径-20261021`，归档时一起保存。

Logic 11668、Register 3705、BSRAM 40/46、DSP 1.75/24，Fmax 39.408MHz，setup +11.662ns、hold +0.318ns，负裕量端点 0。最差路径仍经过分配器选择逻辑。没有完整门禁、再次综合、烧录或真实外设验证。

复现：在项目工作区用现有 Python 运行 `commands/run_review.py`。编译采用 `C:/iverilog/bin/iverilog.exe -g2012 -DSIMULATION -I . -s tb_event_prefetch`，输入为该测试、所有 `rtl/audio/*.v`、`rtl/top.v` 与 `sim/gowin_prom_model.v`，工作目录为生产 source；运行用 `vvp.exe`。已有结果无需重复生成。

`audit_changes.patch` 仅包含本轮新增测试与门禁登记，回退后不影响已有 RTL。`packaging.json` 为清理记录；新归档 `archive/FPGA-20261021-v0.6` 包含 SHA256 清单。`before/top.v` 是第三项完成时的源码，可用于回退第四项；回退后应重新仿真、构建。
