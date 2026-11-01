# 优化 03 审核证据

结论：发现 F6 持键重复报告会再次切换，已直接修复，三个相关短测试和一次修正后构建通过。没有硬件烧录或完整长门禁。

`before/` 保留修正前 HID、连接模块和顶层源文件。`tb_hid_repeat_review_before_run.log` 是修改前复现失败，`before_results.json` 的通过表示“成功复现预期失败”，并非原功能通过。`after_results.json` 记录修正后三台短测试全部退出 0，日志分别保留编译与运行结果。审核测试源在 `source/`，产品测试改动在生产 `source/sim` 中。

`build_after.log` 为修正后唯一一次构建日志；`build_reports/`、`debug8usb.receipt.json` 与 `metrics_after_fix.json` 对应同次成功构建。Logic 11537、寄存器 3689、BSRAM 40/46、DSP 1.75，Fmax 31.938MHz，setup +5.727ns、hold +0.319ns。222 个输入、摘要、位流和工具版本已核对；位流未烧录。原实现的旧位流及指标保留在相邻 `FPGA-优化03-HID控制-20261021` 目录。

在项目根目录使用现有 Python 运行 `commands/run_review.py --phase after --top`，只跑本轮三个短测试，依赖 `C:/iverilog/bin`。需要复现修改前错误时使用 `--phase before`，读取已保存的旧 keymap，不覆盖快照。构建命令为 `& ./output/handoff_milestone2_20261008/source/build/build.ps1 -Profile debug8usb -GwSh 'E:/Gowin/Gowin_V1.9.11.03_Education_x64/IDE/bin/gw_sh.exe'`。`commands/collect_build.py` 收集当前成功构建并核对内容绑定；只在需要新证据时运行，已有证据无需重复生成。

归档与清理记录见 `packaging.json`。修正差异为 `review_fix.patch`；完整第三项相对 Git HEAD 的改动为 `third_item.patch`。硬件键盘、PCM5102A 与实际音频效果尚未验证。
