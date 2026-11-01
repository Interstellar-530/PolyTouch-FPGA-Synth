# 2026-10-22 版本合流证据

`relationship.json` 记录 v2.0.0 共同祖先、v2.1.0 与队友提交、双方独立提交数和最终取舍。`before/ours`、`before/teammate` 保存双方四个测试台的原始 Git 字节；`prepare_merge.py` 是本次冲突处理的可核对记录，重复执行不会覆盖快照。

`before_results.json` 和 before 日志记录本方原样测试的两处真实失败，不能当作通过。`after_results.json` 与 after 日志记录四个合流测试、力度全量边界回归的成功结果，以及生产 192 输入/位流、原型 21 输入不变。编译和运行均限定 45 秒，没有启动完整长门禁或实现工具。

在仓库根运行 `python -B docs/evidence/FPGA-版本合流-20261022-v0.1/commands/run_checks.py` 可复现合流检查；加 `--before` 从已保存快照复现合流前结果。需要本机 Python 和 C:/iverilog/bin。现有证据充分，无需重复运行。原先已核对的绝对构建路径来自本机 v2.1.0 凭据，换机器重新构建即可。

本次临时目录 `tmp/merge-review-20261022-v01` 在保存日志后清理，具体目标在 `cleanup_inventory.json`。`archive/FPGA-20261022-v0.1` 保存完整交付与 SHA256。生产功能、波表及资源使用不变，晶振和板级音频后续验收。
