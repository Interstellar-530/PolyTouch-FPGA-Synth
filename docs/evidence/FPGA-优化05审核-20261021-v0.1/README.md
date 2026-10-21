# 第五项音质审核证据

结论：吉他无损；钢琴是小幅有损近似，主要谐波变化很小，但不能认定完全无音质下降。资源节省 15 块 BSRAM 有效。本轮不改生产波表或 RTL。

`commands/analyze_quality.py` 用现有 numpy 环境，独立比较第四项归档与现有全部逻辑表、pROM 初始化、512×512 整数插值、主要谐波及现有 WAV。结果在 `quality_analysis.json` 和 `analysis.log`。其中 −600dB 只是为精确零差异设置的数值显示下限，实际是否相同以 `equal`、`exact_equal` 和误差 0 为准。

`commands/run_rtl_ab.py` 保存旧引擎和 ROM 到 `before/`，生成 `source/tb_bank_audio_ab.v`，仅在 `tmp/bank-review-20261021-v01` 改名参考模块及编译。`rtl_ab_results.json`、日志和 `rtl_pairs.csv` 记录 104 配置、6656 帧通过。阶段等待被加速，单声部激活于 8 声部配置，未渲染完整顶层。`setup_unicode_path.log` 为初次路径准备失败记录，未计为通过。

`audio/piano/ab.wav` 为前后同乐句，中间静音；亮音色 tone=4、力度 127，音符 60/72/76/83/84/95。`audio/guitar/` 覆盖六个频段，力度 100。各目录另有 before、after、差分放大 40dB 及模型读数，生成日志在 `render_*.log`。所有 WAV 都是近似波表模型，合成包络且未包含生产 F=2 增益、低通和 VCA，不是实机录音或盲听结果。

`commands/collect_build.py` 仅核对现有构建，未调用综合器；`metrics_verified.json` 核对 192 输入、摘要、位流及工具版本。`build_reports/` 与成功凭据属于同一第五项位流。相邻原实现目录保留历史输入数据、旧模型 WAV 和报告，旧 `audible?` 结论已在其 README 明确撤销。

复现需现有 Python/Icarus 和 `tools/.venv-audio-analysis`。先运行 `run_rtl_ab.py`，再用 numpy 环境运行 `analyze_quality.py`；如需重建模型试听，按 `render_piano.log` 所述参数调用 `tools/render_bank_ab.py`，输入为原实现 `banks_before` 和当前 bank HEX。已有证据无需重复测试。归档的 `REPRODUCE.md` 提供完整命令。

审核更正前的试听工具、说明及旧 RTL 在 `before/`，`audit_changes.patch` 记录更正；`packaging.json` 记录临时文件清理。关键归档 `archive/FPGA-20261021-v0.7` 还包括生产源快照、生成/试听工具、目标位流和 SHA256。原始素材、工具环境与历史构建保留。
