"""Write entry points for the approved chronological layout (2026-11-01)."""
import json
from reorganize_repository import ROOT, REPORT, AUDIT, write


def main():
    write(ROOT/'README.md', '''# PolyTouch FPGA Synth

高云 GW2A-18 / Sipeed Tang Primer 20K Dock 3714 电子乐器项目。当前源码在 [`source/`](source/)，历史版本按日期保存，入口为[版本时间线](docs/history/VERSIONS.md)。

当前功能基线为 **2026-10-30 最终交付**，原标签 `final-20261030`，实现提交 `ede17ff`、冻结提交 `efd76ea`。该版为 32 声部 HDMI 乐器，音频由 FPGA 实时合成。原始交付包、位流与验证范围见[最终交付说明](releases/2026/10/FPGA-20261030-v0.1/original-delivery/README.md)。归档编号 v0.N 只表示同日保存顺序，原语义版本与标签保持不变。

| 需要的内容 | 入口 |
|---|---|
| 当前 RTL、测试、约束与构建 | [`source/`](source/README.md) |
| 各日期版本与阶段源码 | [版本时间线](docs/history/VERSIONS.md) |
| 项目规划、设计和比赛资料 | [文档目录](docs/README.md) |
| 接线、采购和硬件搭建 | [`docs/hardware/`](docs/hardware/) |
| 仿真、构建和烧录原始证据 | [`evidence/`](evidence/README.md) |
| 独立实验与未合并候选 | [`experiments/`](experiments/README.md) |
| 演示图稿、试听与素材 | [`media/`](media/README.md) |
| 迁移映射与本次验证 | [目录整理记录](evidence/2026/11/FPGA-20261101-reorganization-v0.1/README.md) |

在仓库根目录运行：

```powershell
& './source/sim/run_simulation.ps1' -Suite Quick
& './source/build/build.ps1' -Profile hdmi
```

本机需要 Gowin EDA 与 Icarus Verilog；其他硬件配置和参数见 [`source/build/README.md`](source/build/README.md)。普通构建使用入库的 ROM/HEX；重新生成音色可能需要原样本和额外依赖。烧录应使用新路径生成的构建收据，并执行仿真门禁，不能直接复用旧绝对路径收据。

2026-11-01 的修改是目录和版本归档整理，未改 RTL 功能，也未烧录。原交付中的仿真、时序和 Flash 结果仍是当时的记录，实物冷启动与听感等未完成项目不因此变为已通过。完整历史首页保存在[迁移前 README](docs/history/README-before-20261101.md)。
''')
    write(ROOT/'source/README.md','''# 当前工程

正式源码由原 `output/handoff_milestone2_20261008/source` 迁移到这里，RTL、ROM 和约束保持原字节。`rtl/` 是音频、输入和显示实现，`sim/` 是自检门禁，`constraints/` 是引脚与时序约束，`build/` 是 Gowin 构建入口，`tools/` 是工程内生成工具。

在仓库根目录运行 `& './source/sim/run_simulation.ps1' -Suite Quick`；构建使用 `& './source/build/build.ps1' -Profile hdmi`。配置说明见[构建说明](build/README.md)，测试说明见[仿真说明](sim/README.md)。

旧路径中的本机 Gowin 输出与收据仍保留，不属于当前源码，也不能作为新路径下的成功构建收据。生成目录 `source/build/gowin_*`、`source/build/receipts` 与 `source/impl` 不入库。历史版本从[时间线](../docs/history/VERSIONS.md)进入。
''')
    write(ROOT/'docs/README.md','''# 文档目录

| 类别 | 内容 |
|---|---|
| [planning](planning/) | 项目规划、赛题和阶段任务 |
| [design/minimum_design](design/minimum_design/) | 最低设计、时钟、信号处理和模块接口 |
| [hardware](hardware/) | 采购、引脚、接线和搭建 |
| [guides](guides/README.md) | 当前构建、仿真、烧录与演奏入口 |
| [references](references/README.md) | 板卡资料、厂商手册和研究参考 |
| [reviews](reviews/) | 审核、资源分析和问题复盘 |
| [history](history/VERSIONS.md) | 日期版本、发布说明、日志与旧路径映射 |
| [exports/pdf](exports/pdf/) | 已导出的 PDF 成品 |

旧文档里的“当前”“本轮”以文档自身日期为准。当前工程与最近交付状态以根目录 README 为入口，验证结果以原始证据为准。
''')
    write(ROOT/'docs/guides/README.md','''# 使用入口

当前源码位于 `source/`。从仓库根目录运行 `& './source/sim/run_simulation.ps1' -Suite Quick` 执行短门禁；完整历史回归使用 `-Suite Full`。构建运行 `& './source/build/build.ps1' -Profile hdmi`，其他档位见[构建说明](../../source/build/README.md)。

烧录入口是 `source/build/program_sram.ps1`，必须使用新路径下的构建收据并通过仿真。本次整理没有进行烧录，也没有生成新位流。电脑端演奏工具见[串口键盘](../../tools/serial_keyboard/README.md)。硬件接线按[硬件资料](../hardware/)及对应日期版本的验收范围核对。

历史版本需要在独立工作树中按当时的 README 复现，见[版本时间线](../history/VERSIONS.md)。
''')
    write(ROOT/'docs/references/README.md','''# 参考资料

`boards/` 保存原 board_docs 中的板卡规格、原理图和工具指南；`handoff-20261008/` 保留旧交接包附带的原始参考资料；`research/` 保存研究记录。PDF 成品另外放在 `docs/exports/pdf/`。

本轮只归类文件，没有重新解释原理图或核定数值。历史包中的重复原件保留，以免破坏原包可追溯性；各路径及文件校验可在迁移清单中核对。外部资料沿用原版权和许可，不因本仓库归档而改变。
''')
    branches=json.loads((REPORT/'branch-inventory.json').read_text(encoding='utf-8'))
    write(ROOT/'experiments/README.md','''# 独立实验和候选

按年、月和版本日期保存。目录日期是该快照对应提交的日期；原分支名只用于来源追溯。这里的工程不直接替代根目录 source。

2026-10-27 的 hdmi-import 保留了旧根目录独立副本，hid-review 保留了原已入库审核归档，均保持原字节。其他独有候选保存 source.zip、changes.patch、来源提交及校验记录；完整复现使用原提交的独立工作树。

| 日期 | 候选来源 | 独有提交数 |
|---|---|---|
'''+''.join(f"| {r['timestamp'][:10]} | `{r['ref']}` | {len(r['unique_commits'])} |\n" for r in sorted(branches,key=lambda r:r['timestamp']) if r['unique_commits'])+'\n详细提交列表见[分支清单](../evidence/2026/11/FPGA-20261101-reorganization-v0.1/branch-inventory.json)。已合并阶段快照另见[版本时间线](../docs/history/VERSIONS.md)。\n')
    write(ROOT/'evidence/README.md','''# 验证证据

按年/月归类，目录或文件名保留原日期与主题。仿真、构建、烧录收据、原始日志、指标和关键截图保持原字节；内部旧绝对路径不重写，使用[路径映射](../docs/history/PATHS.md)追溯。

2026-11-01 整理记录位于 [FPGA-20261101-reorganization-v0.1](2026/11/FPGA-20261101-reorganization-v0.1/README.md)。历史失败、未运行和待现场确认的内容沿用原结论。本次分类不新增历史功能验收结果。
''')
    write(ROOT/'media/README.md','''# 媒体与试听

`previews/20261008` 保留旧交接包已入库的试听文件。`previews/undated` 保存原本未入库的过程试听、曲谱截图及捕获数据，文件名中的版本后缀保持不变。未确认产出日期的资料不根据文件修改时间补造日期。

这些素材用于研究、试听和演示，不能替代 RTL 或板级验证证据。曲谱、采样与参考音频沿用原来源及许可；发布或对外分发前仍需核对对应权利。
''')
    # Point project instructions at the new maintained entry points.
    path=ROOT/'AGENTS.md'
    text=path.read_text(encoding='utf-8-sig')
    text=text[:text.index('## 参考文件')]+'''## 参考文件

项目主规划是 `docs/planning/电子乐器项目规划.md`，最低实现分册在 `docs/design/minimum_design`，原理图在 `docs/references`，证据按日期位于 `evidence/年/月`，最终 PDF 在 `docs/exports/pdf`。当前工程在 `source/`，历史版本入口是 `docs/history/VERSIONS.md`，日期交付包在 `releases/年/月/FPGA-日期-v0.N`，本机完整过程备份在 `archive/`。
'''
    write(path,text)
    write(AUDIT/'REPRODUCE.md','''# 复现与回退

迁移前基线为 efd76ea14bab93521604819756410898eb0bc8af。before-files.zip 保存迁移前 3780 个原文件，before-history.bundle 保存所有本地 Git 引用，git-config-before.txt 保存仓库配置，HEAD-before.txt 保存基线。

复现迁移：在原基线的独立副本中准备迁移前未入库文件，依次运行 `tools/reorganize_repository.py --apply`、`tools/finalize_reorganization.py`、`tools/repair_reorganization_paths.py`、`tools/write_reorganization_docs.py`；最后执行校验脚本与文档化的检查。

回退时先保存当前修改，再在工作区内的独立恢复目录中解压 before-files.zip，并从 before-history.bundle 克隆核对。按 original-files.json 和 path-map.json 映射恢复；不要在当前有未保存修改的目录中直接执行 reset --hard 或覆盖解压。

GitHub 专用代理原为 http://127.0.0.1:7897，本轮按用户要求改为直连。需要恢复时运行 `git config --global http.https://github.com.proxy http://127.0.0.1:7897`。不包含凭据或令牌。
''')
    write(AUDIT/'CHANGES.md','# 变更\n\n2026-11-01：按用户批准的方案整理源码、日期版本、资料和证据；GitHub 改为直连。本机归档原件和 Git 历史保留，未推送、未烧录。详情以 evidence/2026/11/FPGA-20261101-reorganization-v0.1 为准。\n')
    print('Entry points written')


if __name__=='__main__': main()
