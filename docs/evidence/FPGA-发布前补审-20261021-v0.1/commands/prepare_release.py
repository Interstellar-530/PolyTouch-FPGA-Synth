"""Record the completed review and prepare v2.1.0 without running more tests."""
from pathlib import Path
import difflib, hashlib, json, shutil

ROOT = next(p for p in Path(__file__).resolve().parents if (p / '.git').exists())
OUT = Path(__file__).resolve().parents[1]
SRC = ROOT / 'output/handoff_milestone2_20261008/source'
RELEASE = ROOT / 'releases/v2.1.0'

def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p, s):
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(s, encoding='utf-8')
def copy(a, b):
    b.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(a, b)

tests = json.loads((OUT / 'after_results.json').read_text())
metrics = json.loads((OUT / 'metrics_verified.json').read_text())
receipt = json.loads((OUT / 'build_receipt.json').read_text())
assert tests['passed'] and all(row[3] == '0' for row in metrics['tns'][1:])
assert all(sha(Path(k)) == v for k, v in receipt['inputs_sha256'].items())
assert sha(OUT / 'ram32.fs') == receipt['bitstream_sha256']
prod = json.loads((ROOT / 'docs/evidence/FPGA-优化05审核-20261021-v0.1/debug8usb.receipt.json').read_text(encoding='utf-8-sig'))
assert all(sha(Path(x['Path'])) == x['Sha256'] for x in prod['Inputs'])
assert sha(Path(prod['Bitstream'])) == prod['BitstreamSha256']

patch = []
names = [p.relative_to(OUT / 'before') for p in (OUT / 'before').rglob('*') if p.is_file()]
names += [Path('rtl/prototypes') / n for n in ['instrument_ram_audio_compute.v', 'instrument_ram_audio_datapath.v', 'instrument_ram_wavetable_engine.v']]
names += [Path('sim/tb_instrument_rom_banks.v')]
for rel in names:
    before, after = OUT / 'before' / rel, SRC / rel
    if after.exists():
        patch.extend(difflib.unified_diff(before.read_text(encoding='utf-8-sig').splitlines(True) if before.exists() else [],
            after.read_text(encoding='utf-8-sig').splitlines(True), fromfile='a/' + rel.as_posix(), tofile='b/' + rel.as_posix()))
write(OUT / 'audit_changes.patch', ''.join(patch))

report = '''# 发布前新增集成补审（2026-10-21）

补审完成，修正后可随 v2.1.0 发布。新增内容是在独立 32 声部原型接入现有钢琴 12 表、吉他 30 表，并支持音色/钢琴力度档控制。生产顶层仍是 8 声部；本次没有烧录。实际计算时钟由后续到位的晶振提供，不以晶振未到位阻止本次源码发布。

发现并修复了四项已审核调度修正被覆盖的问题：扫描读取排队音符、窃声年龄回绕、配置背压/负载竞态和力度 128 截为静音。四个旧错误均先复现失败，修正后通过。新增 ROM 封装在 CE=0 时错误切回通用表，已改为保持已选 ROM；全部 24576 个地址与 240 次停读保持检查通过。

音色选择改为按音符划分频段，避免 48kHz 下套用 46.875kHz 相位增量阈值而误分 C4 等边界。恢复吉他低音段中低力度使用 variant2 的原规则，钢琴高音组从 MIDI78 开始；切换钢琴档位时对阶段做钳位，避免下溢。bank、weight、包络、力度和相位增量统一快照并保持到接收，音色变更在帧边界锁存。新用例覆盖低音力度、C4、高音组和档位切换下溢。

新增配置字段及八字状态布局隔离到 `rtl/prototypes/instrument_ram_*`，原 `rtl/audio/ram_*` 端口和布局恢复。旧音频路径数值/静音/24 位 I2S 回归通过，解码 721 帧，699 帧低八位非零。生产少表构建的全部 192 个输入及位流 SHA256 仍匹配第五项审核凭据。

32 声部完整路径通过分配、独立音高、窃声、重按、释放、音色选表及 I2S 检查，解码 151 帧。实测最后活动第 992/1024 拍，最多每帧完成 32 个配置。配置采用轮询选择，避免 32 路优先编码器与音高查表串成过长路径；稀疏更新在一轮可用扫描槽内访问，满刷新仍维持每四拍一笔。对应测试等待界限按 32 路扫描更新，未放宽音频帧预算。

第一次实现暴露 Fmax 47.533MHz、setup −0.693ns；修改选择路径后重新实现，Logic 5262、Register 2341、BSRAM 26/46、2×MULT18X18（1 DSP），Fmax 49.302MHz。在 49.152MHz 约束下 setup +0.062ns、hold +0.216ns，负裕量端点为零。21 个输入与原型位流绑定。内部时序余量较小，今后增加功能需重新核算；本次不再追加反复实现。首次未通过报告保存在 `timing_before/`。

没有修改已接受的少表音频数据，第五项音质审核结论继续适用：吉他复用逐位相同，钢琴小幅近似；这不等于完成了 32 声部实机盲听。原型没有板级引脚约束，晶振和实物音频验收留待外设到位后完成。正式烧录前仍执行完整仿真门禁。本轮仅做必要定向验证，未宣称完整门禁通过。

证据见 [补审目录](../evidence/FPGA-发布前补审-20261021-v0.1/README.md)。回退依据为 `before/` 和 `audit_changes.patch`，或恢复 v2.0.0 后重新仿真与构建。
'''
write(ROOT / 'docs/reviews/FPGA-发布前集成补审-20261021-v0.1.md', report)
write(OUT / 'README.md', '''# 发布前补审证据

`before/` 保存收到的未审核集成源码；`before_results.json` 记录四项调度错误及 CE 停读选表错误的成功复现，退出码 1 为预期失败。`after_results.json` 为当前修正后四个测试台的通过记录，调度台默认执行五个用例；日志包含完整帧预算与独立 I2S 解码。源文件 SHA256 在运行前后核对。

`build_receipt.json`、`build_reports/`、`ram32.fs` 和 `metrics_verified.json` 为最终修正版本，一次首次实现发现时序不足后，依据报告修正并重新实现，首次报告保存在 `timing_before/`。两个原型位流都未加板级 CST，不可直接当生产位流使用。

复现定向仿真：在仓库根运行 `python -B docs/evidence/FPGA-发布前补审-20261021-v0.1/commands/run_checks.py`；加 `--before` 复现原错误。需 C:/iverilog/bin。`build_review.py` 使用现有 Gowin V1.9.11.03，在新的临时目录构建；`summarize.py` 只读报告并核对哈希。已有证据足够，无需重复长门禁。`prepare_fixes.py` 是本轮一次性修正过程记录，依赖当时本地归档，不作为普通构建入口。

本轮临时仿真目录和两次 PnR 目录在关键报告与位流留存后清理，清单见 `cleanup_inventory.json`。源文件、可复现命令、证据及既有工具环境保留。交付归档为 `archive/FPGA-20261021-v0.9`。
''')

readme = ROOT / 'README.md'
text = readme.read_text(encoding='utf-8-sig')
start = text.index('## 当前代码与验证范围')
text = '''# PolyTouch FPGA Synth — v2.1.0

2026-10-21 新版整合六项优化与审核修正：力度边界、构建哈希绑定、HID 音色/音量控制、事件预取、钢琴/吉他少表复用，以及独立 32 声部音色原型。当前开发分支为 `codex/s4-s6-pressure`，源码入口仍是 `output/handoff_milestone2_20261008/source`。生产版维持 8 声部；32 声部原型已接入少表音色，实际计算时钟由后续晶振提供。详见 [v2.1.0 说明](docs/releases/v2.1.0.md) 与 [发布前补审](docs/reviews/FPGA-发布前集成补审-20261021-v0.1.md)。

''' + text[start:]
text = text.replace('RGB 灯、彩屏、合唱和 32 声部仍是工作安排中的待办', 'RGB 灯、彩屏、合唱和 32 声部板级集成仍是工作安排中的待办')
old_start = text.index('第六项独立 `ram32_top`')
old_end = text.index('## 历史版本', old_start)
text = text[:old_start] + '''第六项独立 `ram32_top` 及后续钢琴/吉他集成已补审修正：32 声部事件、ADSR、少表音色、24 位 I2S 通过定向验证，实测帧尾 992/1024 拍。BSRAM 26/46、2 个 MULT18X18，49.152MHz 约束下 Fmax 49.302MHz、setup +0.062ns。旧 RAM 接口保留兼容，音色扩展使用独立原型模块。晶振后续到位；板级引脚与实物音频仍待集成，生产版本维持 8 声部。此次不追加完整长门禁或烧录，详见[集成补审](docs/reviews/FPGA-发布前集成补审-20261021-v0.1.md)。

''' + text[old_end:]
text = text.replace('v2.0.1 尚未提交或打 Git 标签；', 'v2.0.1 是本日早期候选记录，其内容纳入 v2.1.0；')
write(readme, text)
early = ROOT / 'docs/releases/v2.0.1.md'
early_text = early.read_text(encoding='utf-8-sig')
write(early, early_text.replace('# PolyTouch v2.0.1 本地候选版', '# PolyTouch v2.0.1 早期候选记录') + '\n本候选没有单独发布；后续六项优化和审核修正统一纳入 [v2.1.0](v2.1.0.md)。本文指标保留为当天早期快照。\n')
prior = ROOT / 'docs/reviews/FPGA-32声部原型效果审核-20261021-v0.1.md'
write(prior, prior.read_text(encoding='utf-8-sig') + '\n后续钢琴/吉他少表集成及回归修正已另行完成[发布前补审](FPGA-发布前集成补审-20261021-v0.1.md)，最新资源为 BSRAM 26/46；本文 5 块资源为此前通用音色原型快照。\n')
index = ROOT / 'docs/版本索引与文件地图-20261014-v0.1.md'
it = index.read_text(encoding='utf-8-sig')
it = it.replace('当前工作分支是 `codex/s3-i2s-tx`，生产发布仍是 `main` 的 `b559237`（v1.01，已写入外部 Flash，User Code 0x5633）。', '2026-10-21 更新：当前工作分支为 `codex/s4-s6-pressure`，本次发布 v2.1.0；生产源码为 8 声部，32 声部少表音色原型独立保留。历史已烧录信息以当日烧录日志为准。')
it = it.replace('（= `origin/main`）', '（历史基线）')
row = '| v2.1.0 六项优化及审核修正 | 标签 `v2.1.0` | 唯一 source 入口，生产 8 声部及独立 32 声部原型 | `docs/releases/v2.1.0.md`、当日 reviews/evidence | `archive/FPGA-20261021-v0.9` | `releases/v2.1.0/debug8usb.fs`（未烧录） |\n'
it = it.replace('| v1.0.0 四声部基线', row + '| v1.0.0 四声部基线')
write(index, it)

copy(Path(prod['Bitstream']), RELEASE / 'debug8usb.fs')
copy(ROOT / 'docs/evidence/FPGA-优化05审核-20261021-v0.1/debug8usb.receipt.json', RELEASE / 'debug8usb.receipt.json')
write(ROOT / 'docs/releases/v2.1.0.md', '''# PolyTouch v2.1.0

日期：2026-10-21；基线 v2.0.0（2d3db6c）。本版汇总今日六项优化、逐项审核修正和发布前新增音色集成补审。生产档仍为 8 声部，保留已接受的钢琴 12 表、吉他 30 表方案。32 声部作为独立原型随源码发布，后续接入晶振及板级引脚。

| 项目 | 本版效果与审核 |
|---|---|
| 力度边界 | 128..255 饱和为 127，避免截为静音；生产与原型一致 |
| 构建绑定 | 输入及位流 SHA256 凭据，烧录前拒绝过期产物；生成工具使用可定位路径 |
| HID 控制 | F6 切换音色，↑/↓ 以 5 调音量并限制 0..100；修复 F6 持键重复报告触发 |
| 事件预取 | 寄存后再进入分配器，缩短仲裁路径；定向顺序/背压检查通过 |
| 少表复用 | 生产 BSRAM 40→25/46；吉他逐位相同，钢琴最差单表误差 −60.73dB，主要谐波最大幅度差 0.0314dB，6656 帧 RTL 配对通过；未作实机盲听 |
| 32 声部原型 | 事件、包络、独立音高、窃声、重按、释放和 24 位 I2S；恢复四项调度修正，接入少表音色并修复 ROM CE 保持、频段/力度映射及阶段下溢 |

生产 `debug8usb` 位流为 PT8211 调试档：Logic 11392，Register 3702，BSRAM 25/46，DSP 1.75；Fmax 37.890MHz，setup +10.645ns、hold +0.208ns。其全部 192 个构建输入与第五项审核凭据仍匹配。位流位于 [debug8usb.fs](../../releases/v2.1.0/debug8usb.fs)，SHA256 `1d3a8849f67bd2bd25ff7f9a9de4ed00e5c52aab141d9f60b9fe932fae7abc5d`，本次未烧录。`standard27` 是 PCM5102A 标准 I2S 入口，本次未重做其 PnR。

最终 32 声部音色原型：Logic 5262、Register 2341、BSRAM 26/46、2×MULT18X18。实测帧尾 992/1024 拍；49.152MHz 内部约束下 Fmax 49.302MHz、setup +0.062ns、hold +0.216ns，负端点零。内部时序余量较小；实际时钟由后续晶振提供，本次不以外设未到位阻止发布。原型位流无板级 CST，不作生产烧录产物。

验证采用各项已有证据和必要定向回归；补审覆盖 24576 个 ROM 地址、240 次 CE 停读保持、五项调度用例、32 声部完整数字路径及旧音频接口。首次集成实现的时序不足已按报告修正并复验，未反复运行无效长门禁。完整门禁未在本轮全部执行，正式烧录前仍为默认前置条件。

详见 [优化路线与优先级](../reviews/FPGA-Git差异与优化方向-20261021-v0.1.md)、[第五项音质审核](../reviews/FPGA-波表复用音质审核-20261021-v0.1.md)、[第六项历史审核](../reviews/FPGA-32声部原型效果审核-20261021-v0.1.md) 和 [最终集成补审](../reviews/FPGA-发布前集成补审-20261021-v0.1.md)。不依赖外设的六项已完成本轮审核；触摸、压力、实体 USB 键盘、模拟听感和晶振接线待硬件到位后验收。

普通复现按项目 README 调用 build/build.ps1；入库 HEX 和 ROM 可直接使用。构建凭据记录原机器绝对路径与原始文件字节，换机器或换行转换后应重新构建生成新凭据。`source-manifest.sha256` 记录 Git 暂存区规范化后的源码/工具字节，便于核对发布内容；本地归档单独保存原始字节校验。

本地完整归档 `archive/FPGA-20261021-v0.9` 包含源文件、两类目标位流、复现命令、证据、变更说明、MANIFEST 与 SHA256。仅清理本轮明确的临时仿真和实现目录；历史产物、原始素材及工具运行环境保留。回退源码使用 v2.0.0 或各项 before/补丁，重新执行所需仿真和构建；Git 推送使用普通快进，不改写远端历史。
''')
write(RELEASE / 'MANIFEST.md', '''# FPGA-20261021-v0.9 / Git v2.1.0

`debug8usb.fs` 为第五项审核后生产 8 声部 PT8211 调试位流，未烧录；`debug8usb.receipt.json` 为原始 192 输入绑定。`source-manifest.sha256` 覆盖 Git 暂存区规范化后的唯一 source 与相关工具，`checksums.sha256` 覆盖本目录产物及清单。源码、复现与验证范围见 docs/releases/v2.1.0.md。

32 声部少表音色原型的报告、21 输入凭据和无板级 CST 位流见 docs/evidence/FPGA-发布前补审-20261021-v0.1。实际时钟由后续晶振提供，生产/原型位流用途不同。完整本地原始字节归档为 archive/FPGA-20261021-v0.9。
''')
attrs = ROOT / '.gitattributes'
at = attrs.read_text()
if '\n*.fs binary\n' not in at: write(attrs, at + '\n# FPGA bitstreams must preserve their receipt-bound bytes.\n*.fs binary\n')
print('Review and release documents prepared; production 192 inputs and prototype 21 inputs verified.')
