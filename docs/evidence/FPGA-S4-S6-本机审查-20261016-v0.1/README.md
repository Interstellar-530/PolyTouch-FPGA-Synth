# S4-S6 本机定向审查证据

日期 2026-10-16，审查提交 `40ef0128dadffdcbae221b79e7ee1bac11cf9ef0`。

`simulation_results.json` 记录本机八项定向仿真的命令、工作目录、退出码与耗时；每项有编译和运行日志。没有调用完整 `run_simulation.ps1`，没有烧录或新综合。`tb_review_top` 是已知缺陷复现测试，不能把其 PASS 理解为压力表情完成。

`default-build-entry.json/log` 是旧默认构建清单的编译展开，预期报缺四个模块（退出码 5）；`audit_build_entry.py` 捕获此缺陷后自身退出 0。`numerical_metrics.json` 是独立数值分析，含 4096 码的除法替代等价、全映射音分误差、最坏相位混音和时钟预算。数值分析不提供优化后综合资源结论。

复现时从 `archive/FPGA-20261016-v0.1/source/source-snapshot.zip` 解压源码，设置命令里的 source/snapshot 位置即可。Icarus 路径可在 runner 参数中调整。本机 Windows 沙箱内编译器发生访问异常，沙箱外实际通过；日志中的中文目录若显示问号是 Icarus 路径输出编码，不影响测试结果。没有跳过失败断言。

```powershell
$py = 'C:\Users\ROG\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
$evidence = 'docs/evidence/FPGA-S4-S6-本机审查-20261016-v0.1'
$snapshot = '<解压后的源码快照根目录>'
$source = Join-Path $snapshot 'output/handoff_milestone2_20261008/source'
& $py (Join-Path $evidence 'run_targeted.py') --source $source
& $py (Join-Path $evidence 'analyze_review.py') --snapshot $snapshot
& $py (Join-Path $evidence 'audit_build_entry.py') --source $source
& 'tools/.venv-docconvert/Scripts/python.exe' (Join-Path $evidence 'build_wiring_pdf.py') `
  'docs/hardware/FPGA-完整接线方案-20261016-v0.1.md' `
  'output/pdf/FPGA-完整接线方案-20261016-v0.1.pdf'
```

`layout_review.json` 保存最终 PDF 六页人工视觉检查结论；排版缩略图是复核证据，原理图与手册的一次性 PNG 不保留。`pin_crosscheck.json` 只比对本方案使用的 21 条信号与同提交的 CST，不替代实物测量。

完整判断见 `docs/reviews/FPGA-S4-S6-本机审查-20261016-v0.1.md`。原始生产代码仍在原分支，修改建议没有被悄悄应用。
