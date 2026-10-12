# 共享审查包清单

基线：GitHub `main` 提交 `2c3846c49c75d701bde2352b84cfa3a36316abbb`。本包是报告与证据，不是可烧录版本。所有列出的文件均有 `checksums.sha256` 记录，校验文件自身除外。

| 类别 | 文件 | 说明 |
| --- | --- | --- |
| 目标产物 | `FPGA项目进展与月底方案-20261012-v0.1.md` | 进度、串口、架构、工时与风险审查 |
| 目标产物 | `FPGA外设复查清单-20261012-v0.1.xlsx` | 30 项物料和板载资源复查 |
| 执行计划 | `零外设可执行任务-20261012.md` | 当前无外设时可完成的任务及验收界限 |
| 源数据 | `peripherals.json` | 工作簿原始行与来源 |
| 测试源文件 | `tb_adsr_release_audit.v` | 自检 ADSR 释放缺陷，基线预期失败 |
| 验证工具 | `verify_workbook.py` | 只读复开验证 Excel 公式缓存和结构 |
| 仿真证据 | `rtl_baseline_simulation.txt`、`adsr_release_audit.txt` | 原门禁通过、补充回归失败 |
| 构建证据 | `instrument.rpt.txt` | 隔离 PnR 资源及时序报告 |
| 串口证据 | `serial_protocol_probe.json` | COM13 收到无副作用指令的错误回复 |
| 复现说明 | `REPRODUCE.md` | 仿真与表格检查命令 |
| 变更说明 | `CHANGELOG.md` | 影响、验证与回退 |
| 包说明 | `README.md` | 范围和本地完整归档位置 |
| 字节保真 | `.gitattributes` | 只对本目录停用 Git 换行转换，保持 SHA256 在检出后稳定 |

本机完整 `archive/FPGA-20261012-v0.1` 保存原始 PDF 转换、板卡图片及硬件只读证据，依仓库忽略规则不参与本次推送。保留这些原始证据供现场复核；没有把构建缓存和故障码流上传。
