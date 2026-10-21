"""Archive the RAM32 audit, verify hashes, and clean only its two temp roots."""
from pathlib import Path
import difflib,hashlib,json,shutil,stat,subprocess
ROOT=next(p for p in Path(__file__).resolve().parents if (p/'.git').exists())
OUT=Path(__file__).resolve().parents[1];REL=Path('output/handoff_milestone2_20261008/source');SRC=ROOT/REL
ARCHIVE=ROOT/'archive/FPGA-20261021-v0.8'
IMPL=ROOT/'docs/evidence/FPGA-优化06-32声部原型-20261021'
assert not ARCHIVE.exists(),'Never overwrite an existing archive'
def copy(src,dst):dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,dst)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()

changes=[]
for name in ['rtl/prototypes/voice_sched32.v','sim/tb_ram32_complete.v','sim/run_simulation.ps1','sim/tb_voice_sched32_review.v']:
    old=OUT/'before'/name
    changes.append((SRC/name,old if old.exists() else None))
changes.extend([(ROOT/'README.md',OUT/'before/project_README.md'),(IMPL/'README.md',OUT/'before/implementation_README.md')])
patch=[]
for current,old in changes:
    patch.extend(difflib.unified_diff(old.read_text(encoding='utf-8-sig').splitlines(True) if old else [],
        current.read_text(encoding='utf-8-sig').splitlines(True),fromfile='a/'+current.relative_to(ROOT).as_posix() if old else '/dev/null',
        tofile='b/'+current.relative_to(ROOT).as_posix()))
(OUT/'audit_changes.patch').write_text(''.join(patch),encoding='utf-8')

receipt=json.loads((OUT/'build_receipt.json').read_text())
assert sha(OUT/'ram32.fs')==receipt['bitstream_sha256']
assert all(sha(Path(k))==v for k,v in receipt['inputs_sha256'].items())
roots=[ROOT/'tmp/ram32-review-20261021-v01',ROOT/'tmp/ram32-review-pnr-20261021-v01']
inventory=[]
for root in roots:
    resolved=root.resolve();assert resolved.parent==(ROOT/'tmp').resolve() and not root.is_symlink() and not root.is_junction()
    paths=list(root.rglob('*'))
    assert all(p.resolve().is_relative_to(resolved) and not p.is_symlink() and not p.is_junction() for p in paths)
    inventory.append(dict(root=str(resolved),files=[str(p) for p in paths if p.is_file()]))
assert not roots[0].exists() or set(p.name for p in roots[0].iterdir())=={'scheduler_before.vvp','scheduler_after.vvp','complete_after.vvp'}
inventory_path=OUT/'cleanup_inventory.json'
if not inventory_path.exists():inventory_path.write_text(json.dumps(inventory,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('Cleanup roots: '+json.dumps([x['root'] for x in inventory],ensure_ascii=False)+
      '; files='+str(sum(len(x['files']) for x in inventory)),flush=True)
for root in roots:
    if root.exists():
        # Gowin marks .bin/.binx/.fs read-only. Only this validated temporary
        # tree is changed, after its key bitstream/reports have been preserved.
        for path in root.rglob('*'):
            if path.is_file():path.chmod(path.stat().st_mode | stat.S_IWRITE)
        shutil.rmtree(root)
record=dict(archive=str(ARCHIVE),cleanup_roots=[str(p) for p in roots],cleanup_completed=all(not p.exists() for p in roots),
            production_rtl_or_rom_changed=False,prototype_scheduler_fixed=True,prototype_builds=1,hardware_programmed=False,
            generated_readonly_files_handled=True)
(OUT/'packaging.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

ARCHIVE.mkdir(parents=True)
files=subprocess.check_output(['git','ls-files','-c','-o','--exclude-standard','-z','--',REL.as_posix()],cwd=ROOT).decode().split('\0')
for name in filter(None,files):
    path=ROOT/name
    if path.is_file():copy(path,ARCHIVE/'source'/path.relative_to(SRC))
for path in ['rtl/prototypes/voice_sched32.v','sim/tb_ram32_complete.v','sim/tb_voice_sched32_review.v']:
    assert sha(ARCHIVE/'source'/path)==sha(SRC/path)
shutil.copytree(OUT,ARCHIVE/'evidence/review');shutil.copytree(IMPL,ARCHIVE/'evidence/implementation')
copy(OUT/'ram32.fs',ARCHIVE/'target/ram32_prototype.fs')
copy(ROOT/'docs/reviews/FPGA-32声部原型效果审核-20261021-v0.1.md',ARCHIVE/'target/审核结论.md')
copy(ROOT/'README.md',ARCHIVE/'target/README.md')
for name,hash_value in receipt['inputs_sha256'].items():assert sha(ARCHIVE/'source'/Path(name).relative_to(SRC))==hash_value
(ARCHIVE/'MANIFEST.md').write_text('''# FPGA-20261021-v0.8

第六项独立 32 声部原型审核，2026-10-21。source/ 是当前工程源文件、测试、波表、构建配置及原型；target/ 保存审核结论、项目说明和无板级管脚约束的原型位流，不能替代生产位流。evidence/review/ 为本轮修改前快照、四项错误复现、修正后短测试、独立 I2S 解码、实际帧尾预算、一次 PnR、SHA256 凭据及清理清单；evidence/implementation/ 保留初版历史源码/报告/日志。

生产第五项少表方案与 8 声部位流未改变。原型仅有正弦/通用明亮表，无钢琴/吉他音色集成、PLL 时钟源、板级引脚和 IO 验收。本轮未运行完整长门禁或烧录。原始素材、运行依赖、既有历史构建保留。checksums.sha256 覆盖除自身外全部归档文件。
''',encoding='utf-8')
(ARCHIVE/'CHANGELOG.md').write_text('''# 变更说明

修复调度器使用排队音符污染当前事件扫描、5 位年龄回绕、配置 valid/负载未遵守背压及 128 力度截为 0。新增四个短回归，并将它们和完整原型测试登记门禁。完整测试加入 I2S 24 位独立解码及实际最后活动沿计数，实测帧尾为 992/1024，纠正旧 967 拍估算。

修正后四用例和完整路径通过，151 个立体声帧一致。一次新 PnR：Logic 4635、Register 2252、BSRAM 5/46、2×MULT18X18，Fmax 51.922MHz，49.152MHz 约束下 setup +1.085ns、hold +0.425ns、负端点 0。18 个原型输入及位流绑定，生产 192 输入仍匹配第五项。审核增量由 audit_changes.patch/before 可回退，回退后重新仿真和构建。
''',encoding='utf-8')
(ARCHIVE/'REPRODUCE.md').write_text('''# 复现入口

已有证据足够支持本次审核，无需重复测试。需要复现时，在原项目根目录使用现有 Python 与 C:/iverilog/bin，运行 docs/evidence/FPGA-优化06审核-20261021-v0.1/commands/run_review.py --phase before 或 --phase after。--phase before 从保存的旧源码复现四项失败；--phase after 跑四项修正回归及完整路径；--default-only 只验证门禁默认四用例。脚本定位最近 Git 根及生产 source。

commands/build_review.py 使用 Gowin V1.9.11.03，仅在新的 tmp/ram32-review-pnr-20261021-v01 构建独立原型，包含前后输入哈希和位流记录；summarize.py 读报告及凭据，不调用综合器。归档 source 可用于恢复相同工程，但必须保留对应目录结构并重新生成路径凭据。

原型位流没有板级 CST 或时钟源，不是生产发布。烧录任何修改前仍需项目规定的完整仿真及板级配置。原型输入/输出路径记录用于追溯，临时 PnR 工程已在报告/位流留存后清理。
''',encoding='utf-8')
entries=sorted(p for p in ARCHIVE.rglob('*') if p.is_file())
lines=[sha(p)+'  '+p.relative_to(ARCHIVE).as_posix() for p in entries]
(ARCHIVE/'checksums.sha256').write_text('\n'.join(lines)+'\n',encoding='utf-8')
assert all(sha(ARCHIVE/line[66:])==line[:64] for line in lines)
print(f'Archive ready: {ARCHIVE}; {len(entries)} files verified; temporary roots removed.',flush=True)
