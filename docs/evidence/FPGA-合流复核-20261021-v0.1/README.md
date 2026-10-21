# FPGA 合流复核证据

2026-10-21。GitHub `main` 和本地基线都是 `2d3db6c`。本轮是在已有合流上恢复严格缺失测试检测、扩充已有产品测试的门禁注册，并重新构建实际 USB 调试档；未改生产 RTL 和约束。详细结论见 `docs/reviews/FPGA-Git差异与优化方向-20261021-v0.1.md`。

| 证据 | 内容 |
|---|---|
| `git_audit.json` | 所有远端分支与当前 HEAD 的独有提交数、6 个旧提交、68 个审查文件比对与源码 SHA256 |
| `focused_checks.json` | 初次限时检查：9 个原始台通过，原 `tb_top_switch` 在 60 秒停止，另有两档展开、门禁负例和 ROM 重建 |
| `focused_switch_retry.json` | 仅补短窗口音色切换；所有原断言/真实 UART 保留，三处 1500 帧等待缩为 16 帧；通过 |
| `verification_summary.json` | 汇总本次通过的检查、未完成的长测试和未做的硬件验证 |
| `piano_regeneration.json` | 入库 HEX 重建 ROM 的文本/RTL token 对照，除首行注释外一致 |
| `debug8usb_build.log`、`build_metrics.json`、`build_reports/` | 本次综合/PnR、40/46 BSRAM、全部乘法器类别、Fmax 与裕量，含输入内容哈希 |
| `full_gate*.log`、`long_gate_status.txt` | 已停止的全量尝试；沙箱尝试 Icarus 崩溃，沙箱外尝试在用户要求后停止，均不是完整 PASS |
| `preserved_local_files.json` | 原有未跟踪位流、PDF 和报告的校验值，不作本次清理对象 |
| `commands/` | 比较、有限时验证、资源收集与归档脚本 |
| `cleanup.json` | 任务临时目录清理结果及原有文件保留核对 |

在仓库根目录复现只读比较或短检查：

```powershell
git fetch origin --tags
& 'C:\Users\ROG\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' -B '.\docs\evidence\FPGA-合流复核-20261021-v0.1\commands\audit_git.py'
& 'C:\Users\ROG\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' -B '.\docs\evidence\FPGA-合流复核-20261021-v0.1\commands\verify_integration.py'
& '.\output\handoff_milestone2_20261008\source\build\build.ps1' -Profile debug8usb -GwSh 'E:\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\bin\gw_sh.exe'
```

Python 脚本仅使用标准库；可换为本机其他 Python 3。Icarus 固定在 `C:\iverilog\bin`，Gowin 版本为 V1.9.11.03 Education。此 Windows 沙箱内 Icarus 编译会崩溃，定向验证需在本机普通终端或经许可的沙箱外执行。当前默认短检查已改用短窗口切换，不会重跑原 4500 帧切换等待。原始超时记录保留。

完整门禁按用户要求未完成；没有烧录动作，`standard27` 只有展开结果。新位流属于 PT8211 `debug8usb`，不能作为 PCM5102A 档。SHA256 与时序数值以本次 `build_metrics.json` 和原报告为准。
