# 第六项审核证据

独立 32 声部通用音色原型在修正后通过。已直接修复排队音符干扰、年龄回绕、配置 valid/负载背压及力度截断。生产 8 声部、钢琴/吉他少表数据未变。

`before/` 保存审核前的原型调度器、顶层、完整测试和门禁。`before_results.json` 表示四个错误被成功复现，各用例退出 1 并匹配具体失败原因，不代表旧功能正确。`after_results.json` 记录修正后四个用例和完整路径测试通过；`after_gate_default_results.json` 另确认门禁无参数调用可执行全部四项。完整测试扩展 I2S 24 位解码及真实帧尾预算，实际最后活动 992/1024 拍，解码 151 帧。

`commands/run_review.py --phase before|after` 用现有 Icarus 运行对应短检查。`--phase before` 读取已保存旧源码；`--phase after --default-only` 只检查新登记单元台默认入口。源码位于生产 source/sim，源文件与日志均随归档保留。没有运行完整长门禁。

`commands/build_review.py` 对修改后的独立原型执行唯一一次 PnR，构建前后核对 18 输入，保存 `ram32.fs`、`build_receipt.json` 和 `build_reports/`。资源 Logic 4635、Register 2252、BSRAM 5/46、2 个 MULT18X18；Fmax 51.922MHz、setup +1.085ns、hold +0.425ns，负裕量端点 0。`commands/summarize.py` 核对该位流和输入，也核对生产第五项 192 输入及位流保持相同，结果为 `metrics_verified.json`。

该位流是无板级管脚约束的独立原型，时钟来自外部输入，未烧录，不是可替代生产 8 声部的发布物；未集成钢琴/吉他库、时钟产生和生产控制链路。原实现目录的源码/日志/PnR 保留为初版历史，当前结果以本审核目录为准。

`audit_changes.patch` 与 `before/` 可回退审核修正。`packaging.json` 保存临时目标清单及清理结果；新归档 `archive/FPGA-20261021-v0.8` 包含源码、原型位流、复现命令、MANIFEST 和 SHA256。已有运行环境、原始素材和历史构建保留。
