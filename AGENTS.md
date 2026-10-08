# FPGA 项目补充规则

本项目的通用执行规则以全局 `C:\Users\ROG\.codex\AGENTS.md` 为准。下列内容是在此基础上的项目补充。

## 设计与资源约束

当前项目是 2026 年 FPGA 创新设计赛道高云半导体选题二，板卡是 Sipeed Tang Primer 20K Dock 3714，器件是 GW2A-LV18PG256C8/I7，版本 C。最低实现是 4 声部、两个 512 点单周期波表、12 路 MPR121 触摸、1 路 FSR 压力、标准 I2S 到 PCM5102A；板载 PT8211 只作调试。音频路径不使用软核 CPU 或 BL702。

每次增加声部、波表、效果器或显示功能前，先重新计算 BSRAM 块数和 18×18 乘法器数量。32 声部不能使用每声部两个 1024 点波表的并行实现，因为需要 64 块 BSRAM，超过 GW2A-18 的 46 块上限。波表必须使用 Gowin BSRAM ROM IP 或原语，不能用大 `case` 写成 LUT ROM。DDR3 不能用于逐样本波表查表。

## 工作流约束

PDF 阅读默认先转 Markdown，再阅读；PDF 输出默认先写 Markdown，再用 Pandoc + XeLaTeX 生成并复核排版。转换工具在 `tools/docconvert_mcp`，运行环境在 `tools/.venv-docconvert`，OCR 数据在 `tools/tessdata`。原理图、引脚表、精确数值和表单必须渲染 PNG 视觉复核，不能只依赖 OCR。

关键产物按 `FPGA-日期-版本` 归档到 `archive/`。临时文件放在 `tmp/`，任务结束前清理；运行时依赖、工具源码和语言数据不当作临时文件删除。每次归档更新 `MANIFEST.md` 和 `checksums.sha256`。

## 参考文件

项目主规划是 `电子乐器项目规划.md`，最低实现分册在 `docs/minimum_design`，原理图在 `docs/references`，MCP 证据在 `docs/evidence`，最终 PDF 在 `output/pdf`，历史压缩包在 `output`。
