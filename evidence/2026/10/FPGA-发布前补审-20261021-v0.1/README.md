# 发布前补审证据

`before/` 保存收到的未审核集成源码；`before_results.json` 记录四项调度错误及 CE 停读选表错误的成功复现，退出码 1 为预期失败。`after_results.json` 为当前修正后四个测试台的通过记录，调度台默认执行五个用例；日志包含完整帧预算与独立 I2S 解码。源文件 SHA256 在运行前后核对。

`build_receipt.json`、`build_reports/`、`ram32.fs` 和 `metrics_verified.json` 为最终修正版本，一次首次实现发现时序不足后，依据报告修正并重新实现，首次报告保存在 `timing_before/`。两个原型位流都未加板级 CST，不可直接当生产位流使用。

复现定向仿真：在仓库根运行 `python -B docs/evidence/FPGA-发布前补审-20261021-v0.1/commands/run_checks.py`；加 `--before` 复现原错误。需 C:/iverilog/bin。`build_review.py` 使用现有 Gowin V1.9.11.03，在新的临时目录构建；`summarize.py` 只读报告并核对哈希。已有证据足够，无需重复长门禁。`prepare_fixes.py` 是本轮一次性修正过程记录，依赖当时本地归档，不作为普通构建入口。

本轮临时仿真目录和两次 PnR 目录在关键报告与位流留存后清理，清单见 `cleanup_inventory.json`。源文件、可复现命令、证据及既有工具环境保留。交付归档为 `archive/FPGA-20261021-v0.9`。
