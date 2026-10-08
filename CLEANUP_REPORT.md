# FPGA 项目清理与归档报告

## 归档结果

先前会话的产物已经按 `FPGA-20261007-v0.1` 归档到 `E:\Working Space\FPGA\archive\FPGA-20261007-v0.1`。归档包含项目主规划、最低实现全部分册、三份最终 PDF、历史压缩包 v1/v2/v3、转换脚本、PDF 技能源文件、Gowin 与 docconvert 证据、官方原理图、MCP 配置、全局与项目 AGENTS.md，以及 VS Code 工作区文件。

## 清理结果

`tmp` 目录下的全部中间文件已删除，目录本身保留为空。`output\package_v3` 暂存目录已删除，v3 压缩包仍然保留。`tools\AGENTS.updated.md` 已收入归档后删除。项目内的 1821 个 `__pycache__` 缓存目录已删除。

## 保留的运行时依赖

`tools\.venv-gowin-mcp`、`tools\.venv-docconvert`、`tools\vendor\gowin_mcp_server` 和 `tools\tessdata` 属于运行时依赖，不在清理范围内。删除这些内容会同时破坏 Gowin MCP、PDF/Markdown 转换和 OCR 兜底。

## 验证

清理后重新运行了两套 MCP 冒烟测试。Gowin MCP 可以启动 shell、执行 Tcl 并正常退出；docconvert MCP 完成了 Markdown→PDF、PDF→Markdown、Markdown→PDF 的完整往返。最终三份 PDF 保持 A4 版式，关键符号和表格排版正常。

## 规则更新

全局 `C:\Users\ROG\.codex\AGENTS.md` 已更新，新增技能选择表、任务前确认、开源项目复用、文档风格、临时文件清理、日期版本归档、代码修改前说明依据、任务结束四项汇报和受限清理等通用规则。项目级 `E:\Working Space\FPGA\AGENTS.md` 已建立，补充了 GW2A-18 资源边界、PDF/Markdown 默认流程和归档要求。全局文件的更新会在新会话中重新加载；当前会话仍可能使用启动时的旧快照。

## 回退

全局 AGENTS.md 的旧版本保存在 `C:\Users\ROG\.codex\AGENTS.md.bak-20261007`，归档副本在 `archive\FPGA-20261007-v0.1\05_tooling\agents\global-AGENTS-before-20261007.md`。用户级配置和系统 PDF 技能也各自保留了 `bak-20261007` 备份。
