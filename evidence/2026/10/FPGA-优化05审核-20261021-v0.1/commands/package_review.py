"""Archive the fifth-item audio audit, including WAVs, then clean exact temps."""
from pathlib import Path
import difflib,hashlib,json,shutil,subprocess
ROOT=next(p for p in Path(__file__).resolve().parents if (p/'.git').exists())
OUT=Path(__file__).resolve().parents[1]
REL=Path('output/handoff_milestone2_20261008/source')
SOURCE=ROOT/REL
ARCHIVE=ROOT/'archive/FPGA-20261021-v0.7'
IMPL=ROOT/'docs/evidence/FPGA-优化05-波表复用-20261021'
assert not ARCHIVE.exists(),'Never overwrite an existing archive'
def copy(src,dst):
    dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,dst)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()

# Reconstruct the two small pre-audit text snapshots; generation math is unchanged.
gen=ROOT/'tools/gen_epiano_bank.py'
current='''e-piano has about 12 dominant harmonics, so zones 0..4 have only small
differences (worst stage -60.7 dB relative RMS, including low-level
harmonics removed by the original band limits). This is not lossless reuse.
This script therefore emits two groups:'''
previous='''e-piano keeps ~12 harmonics, so zones 0..4 produce the same tables up to float
rounding (-73 dB or lower). This script therefore emits two groups:'''
assert current in gen.read_text(encoding='utf-8')
(OUT/'before/gen_epiano_bank.py').write_text(gen.read_text(encoding='utf-8').replace(current,previous),encoding='utf-8')
control=IMPL/'commands/make_controls.py'
(OUT/'before/make_controls.py').write_text(control.read_text(encoding='utf-8').replace(
    'compaction residual boosted +40 dB; see measured report for level',
    'compaction residual, diff/signal -77.6 dB, +40 dB boost'),encoding='utf-8')
pairs=[(ROOT/'tools/render_bank_ab.py',OUT/'before/render_bank_ab.py'),
       (gen,OUT/'before/gen_epiano_bank.py'),(control,OUT/'before/make_controls.py'),
       (ROOT/'README.md',OUT/'before/project_README.md'),
       (IMPL/'README.md',OUT/'before/implementation_README.md')]
patch=[]
for path,before in pairs:
    patch.extend(difflib.unified_diff(before.read_text(encoding='utf-8-sig').splitlines(True),
        path.read_text(encoding='utf-8-sig').splitlines(True),fromfile='a/'+path.relative_to(ROOT).as_posix(),
        tofile='b/'+path.relative_to(ROOT).as_posix()))
(OUT/'audit_changes.patch').write_text(''.join(patch),encoding='utf-8')

work=(ROOT/'tmp/bank-review-20261021-v01').resolve()
expected={'cases.txt','rtl_pairs.csv','tb_bank_audio_ab.vvp','old_shared_wavetable_engine.v',
          'old_gowin_prom_piano_bank.v','old_gowin_prom_guitar_bank.v'}
targets=list(work.iterdir())
assert work.parent==(ROOT/'tmp').resolve() and not work.is_symlink()
assert {p.name for p in targets}==expected and all(p.is_file() and not p.is_symlink() for p in targets)
assert sha(work/'rtl_pairs.csv')==sha(OUT/'rtl_pairs.csv')
print('Cleanup targets: '+json.dumps([str(p) for p in targets],ensure_ascii=False),flush=True)
for p in targets:p.unlink()
work.rmdir()
record=dict(archive=str(ARCHIVE),cleanup_targets=[str(p) for p in targets],cleanup_completed=not work.exists(),
            production_rtl_or_rom_changed=False,hearing_test=False,additional_synthesis=False,hardware_programmed=False)
(OUT/'packaging.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

ARCHIVE.mkdir(parents=True)
files=subprocess.check_output(['git','ls-files','-c','-o','--exclude-standard','-z','--',REL.as_posix()],cwd=ROOT).decode().split('\0')
for name in filter(None,files):
    path=ROOT/name
    if path.is_file():copy(path,ARCHIVE/'source'/path.relative_to(SOURCE))
for name in ['gen_epiano_bank.py','gen_piano_prom.py','gen_guitar_samples_bank.py','gen_guitar_bank.py','render_bank_ab.py']:
    copy(ROOT/'tools'/name,ARCHIVE/'tools'/name)
shutil.copytree(OUT,ARCHIVE/'evidence/review')
shutil.copytree(IMPL,ARCHIVE/'evidence/implementation')
copy(ROOT/'docs/reviews/FPGA-波表复用音质审核-20261021-v0.1.md',ARCHIVE/'target/审核结论.md')
copy(ROOT/'README.md',ARCHIVE/'target/README.md')
receipt=json.loads((OUT/'debug8usb.receipt.json').read_text(encoding='utf-8-sig'))
copy(Path(receipt['Bitstream']),ARCHIVE/'target/debug8usb.fs')
assert sha(ARCHIVE/'target/debug8usb.fs')==receipt['BitstreamSha256']
for item in receipt['Inputs']:
    assert sha(ARCHIVE/'source'/Path(item['Path']).relative_to(SOURCE))==item['Sha256']
(ARCHIVE/'MANIFEST.md').write_text('''# FPGA-20261021-v0.7

第五项波表复用音质审核，2026-10-21。source/ 为当前生产源码、测试、ROM/HEX 和构建配置，tools/ 为当前生成与试听工具。target/ 包含审核结论、项目说明、未烧录 debug8usb 位流。evidence/review/ 包含全表/频谱/插值分析、RTL 配对结果、旧源码与工具快照、模型 WAV、构建核对及清理记录；evidence/implementation/ 为第五项原始证据和旧试听。

主要结论：吉他逐位无损，钢琴为小幅有损近似；没有盲听或实机音频结论。审核只更正工具和说明，未改生产 RTL/ROM、未重复综合、未执行完整门禁或烧录。依赖环境与原始素材保留。checksums.sha256 覆盖除其自身外全部归档文件。
''',encoding='utf-8')
(ARCHIVE/'CHANGELOG.md').write_text('''# 变更说明

核实全部表和 pROM 初始化、穷举插值并比较实际前后 RTL 6656 帧。吉他 36 张逻辑表全部相同；钢琴 24 张逻辑表被近似替换，最差单表误差 -60.73dB，峰值 79 表采样单位，主要谐波幅度变化最大 0.0314dB。存在低电平带外成分差异，不能按完全无损验收。BSRAM 40→25/46，构建内容匹配。

修正试听模型的整数舍入、阶段长度和吉他低频力度映射；删除用固定相对 dB 判定可闻性的逻辑。更正生成脚本说明和项目/原实现 README。新模型 WAV 另存，旧证据不覆盖。未改生产 RTL 或 ROM。

保真方案可只保留吉他去重并恢复钢琴 36 表，预计 BSRAM 37/46；未切换或做 PnR。audit_changes.patch 与 before/ 可撤回本轮工具/说明更正。完整前后 bank 数据和旧引擎/ROM 可用于另行恢复，但恢复 RTL/ROM 后必须重新仿真构建。
''',encoding='utf-8')
(ARCHIVE/'REPRODUCE.md').write_text('''# 复现入口

现有证据足够支持本次审核，无需重复运行。下列命令从原项目根目录执行，依赖现有 Icarus、Python 与 tools/.venv-audio-analysis。脚本定位最近 Git 根和原生产 source；迁移归档后需恢复对应项目结构与第四项基线。

```powershell
$py = 'C:/Users/ROG/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
& $py -B 'docs/evidence/FPGA-优化05审核-20261021-v0.1/commands/run_rtl_ab.py'
& 'tools/.venv-audio-analysis/Scripts/python.exe' -B 'docs/evidence/FPGA-优化05审核-20261021-v0.1/commands/analyze_quality.py'
& $py -B 'docs/evidence/FPGA-优化05审核-20261021-v0.1/commands/collect_build.py'
```

模型试听调用 tools/render_bank_ab.py，--before-hex 为原实现 banks_before/epiano_bank_all_36.hex，--after-hex 为生产 rtl/audio/epiano_bank_all.hex，--kind piano --notes 60,72,76,83,84,95 --tone 4 --vel 127 --out-dir 指定新目录。吉他改用 guitar_bank_all_36.hex/guitar_bank_all.hex，--kind guitar --notes 40,52,64,71,80,88 --vel 100。

临时输出在 tmp/bank-review-20261021-v01，仅按明确清单清理。已有 WAV 是近似波表模型，未模拟完整音频路径，diff.wav 额外放大 40dB。烧录前仍须完整 RTL 门禁；当前凭据中的绝对路径用于追溯原构建，迁移后需重建。
''',encoding='utf-8')
entries=sorted(p for p in ARCHIVE.rglob('*') if p.is_file())
lines=[sha(p)+'  '+p.relative_to(ARCHIVE).as_posix() for p in entries]
(ARCHIVE/'checksums.sha256').write_text('\n'.join(lines)+'\n',encoding='utf-8')
assert all(sha(ARCHIVE/line[66:])==line[:64] for line in lines)
print(f'Archive ready: {ARCHIVE}; {len(entries)} files verified; temporary directory removed.',flush=True)
