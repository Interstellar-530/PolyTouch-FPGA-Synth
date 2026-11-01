# 构建绑定效果审核证据

结论见 `docs/reviews/FPGA-构建绑定优化效果审核-20261021-v0.1.md`。核心内容是代码审查、现有 11/16 项自检记录核对、当前 222 个输入和位流的独立 SHA256 核对，以及生成器参数/原有重建证据检查；没有再次运行整套测试或重新综合。

`review_results.json` 保存本次只读核对结果及被审脚本哈希。`implementation/` 保存对应的原实现证据。`commands/review_build_binding.py` 是额外位流探针，调用程序始终是本轮模拟脚本；本次仅执行到准备阶段，Get-FileHash 加载失败，没有实际功能结果，不能视为通过。两次准备尝试都没有启动真实烧录或综合，日志保留以避免混淆。

复核核心效果可使用原实现的 `source/build/test_build_inputs.ps1`，不需要 FPGA 或 Gowin。已有 `verify_build_profiles.py` 的 16 项记录同时覆盖构建/烧录入口；本轮没有为确认效果再跑一遍。再制表需要 numpy/soundfile 和原始样本，普通构建使用已有 ROM/HEX，无需下载素材。
