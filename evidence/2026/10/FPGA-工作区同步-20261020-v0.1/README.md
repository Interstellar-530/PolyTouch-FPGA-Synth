# 2026-10-20 工作区版本核对与 GitHub 同步

## 采用的版本

生产代码采用 `output/handoff_milestone2_20261008/source` 当前内容；UI 位于 `tools/serial_keyboard`。工作区遍历检查了 17796 个非工具环境文件，定位 173 份关键源码副本，以 SHA256、构建输入、烧录记录和用途共同判断，不按文件夹日期或修改时间直接覆盖代码。完整结果见 `source-copies.json`。

当前生产 `top.v` SHA256 为 `3AD743087BE28FACD2FAEA361910A6D98B136ED9AAD4FEDD7264662D76DA0958`，与 `archive/FPGA-20261020-v0.6-volume-fix/source/rtl/top.v` 完全相同。最新成功 debug8 构建回执的 222 项输入均与工作区长度和修改时间一致，位流 SHA256 为 `2F8DB574A2ECABE2E71A8B6A8DA32CDAF2EF993F9198AB120CAA15B35DFC8606`。

已读到另一工作树 `C:/Users/ROG/.codex/worktrees/d76d/FPGA` 停在 `057d78c`（10 月 12 日），只有 PuTTY 工具说明/启动文件未提交改动，未将它当作新音频版本。远端另一智能体的 `codex/guitar-preview-ddr3-20261020` 位于 `16f9c32`（10 月 20 日），仅新增吉他试听和 DDR3 独立测试资料，没有修改生产源；已快进纳入当前 `codex/s4-s6-pressure` 分支历史。

## 本次提交范围

10 月 20 日键控响度、主音量、音色包络/表、吉他增益与 24 位低通定标修复；当前仿真脚本/测试台与 UI；此前没有跟踪但被构建引用的钢琴 ROM、键盘 UART 接收模块、standard27 顶层与 CST/SDC；相关复现工具、记录与两份周末工作文档。补入先前未推送的项目证据，保留研究与生产代码的边界说明。

`tools/agent-runtime/` 是约 1.4GB 的本机 JDK/Node/Ghidra 等运行环境，新增忽略规则并保留本地文件。没有把生成的日常 EDA 目录、语言环境、临时编译文件作为最新生产源码。另一智能体已经提交的 DDR3 历史构建证据保持其原提交内容。

## 本轮短检查

运行 `tools/run_sync_checks_20261020.py`，未连接、复位或烧录硬件。Windows 沙箱内 Icarus 重现项目既有 `0xC0000005` 编译崩溃，原始记录在 `checks/`；随后在沙箱外对同一源码运行，结果保存在 `checks-outside/`，11 项命令均退出 0：

| 范围 | 结果 |
|---|---|
| tb_key_gain 编译/运行 | PASS |
| tb_host_kbd 编译/运行 | PASS |
| tb_top_switch 编译/运行 | PASS |
| tb_top_pitch8 编译/运行 | PASS |
| top_dbg8_build 展开 | PASS |
| top_std27_build 展开 | PASS |
| 电脑键盘界面自检 | PASS |

按用户要求没有重跑完整历史门禁、长期稳定性或重新 PnR。历史 PnR/Flash 数据来自相应构建回执和日志；本轮短检查不代表正式外设、模拟音频或端到端延迟通过。新增 CH9350L 控制键、合唱、灯屏和 32 声部仍是计划，未包装成已完成实现。

## 复现

```powershell
& 'tools/.venv-docconvert/Scripts/python.exe' 'tools/audit_workspace_versions_20261020.py' --out 'tmp/source-copies.json'
& 'tools/.venv-docconvert/Scripts/python.exe' 'tools/run_sync_checks_20261020.py' --out 'tmp/sync-checks'
```

第二条在当前 Windows 环境应于沙箱外运行。两脚本均不触碰硬件；仿真临时可执行文件自动清理，证据日志保留。文档任务的一次性下载/转换目录 `tmp/weekend-plan-20261020` 已列出并清理，其核查记录保存在 `archive/FPGA-20261020-v0.7`。

