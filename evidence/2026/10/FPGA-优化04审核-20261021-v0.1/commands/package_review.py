"""Package the fourth-item audit and clean its one exact temporary binary."""
from pathlib import Path
import difflib,hashlib,json,shutil,subprocess
ROOT=next(p for p in Path(__file__).resolve().parents if (p/'.git').exists())
OUT=Path(__file__).resolve().parents[1]
REL=Path('output/handoff_milestone2_20261008/source')
SOURCE=ROOT/REL
ARCHIVE=ROOT/'archive/FPGA-20261021-v0.6'
PREVIOUS=ROOT/'archive/FPGA-20261021-v0.5'
assert not ARCHIVE.exists(),'Never overwrite an existing archive'
def copy(src,dst):
    dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,dst)
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()

copy(PREVIOUS/'source/rtl/top.v',OUT/'before/top.v')
old=(OUT/'before/top.v').read_text(encoding='utf-8-sig')
now=(SOURCE/'rtl/top.v').read_text(encoding='utf-8-sig')
(OUT/'fourth_item.patch').write_text(''.join(difflib.unified_diff(old.splitlines(True),now.splitlines(True),
    fromfile='a/'+(REL/'rtl/top.v').as_posix(),tofile='b/'+(REL/'rtl/top.v').as_posix())),encoding='utf-8')
patch=[]
for name in ['sim/run_simulation.ps1','sim/tb_event_prefetch.v']:
    old_path=PREVIOUS/'source'/name
    old=old_path.read_text(encoding='utf-8-sig').splitlines(True) if old_path.exists() else []
    patch.extend(difflib.unified_diff(old,(SOURCE/name).read_text(encoding='utf-8-sig').splitlines(True),
        fromfile='a/'+(REL/name).as_posix() if old else '/dev/null',tofile='b/'+(REL/name).as_posix()))
(OUT/'audit_changes.patch').write_text(''.join(patch),encoding='utf-8')

work=(ROOT/'tmp/event-review-20261021-v01').resolve()
binary=work/'tb_event_prefetch.vvp'
assert work.parent==(ROOT/'tmp').resolve() and not work.is_symlink()
assert list(work.iterdir())==[binary] and binary.is_file() and not binary.is_symlink()
print('Cleanup target: '+str(binary),flush=True)
binary.unlink();work.rmdir()
record=dict(archive=str(ARCHIVE),cleanup_targets=[str(binary),str(work)],cleanup_completed=not work.exists(),
            production_rtl_changed=False,additional_synthesis=False,hardware_programmed=False)
(OUT/'packaging.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

ARCHIVE.mkdir(parents=True)
tracked=subprocess.check_output(['git','ls-files','-z','--',REL.as_posix()],cwd=ROOT).decode().split('\0')
for name in filter(None,tracked):
    p=ROOT/name
    if p.is_file():copy(p,ARCHIVE/'source'/p.relative_to(SOURCE))
for name in ['sim/tb_top_host_ctrl.v','sim/tb_velocity_bounds.v','sim/tb_event_prefetch.v','build/test_build_inputs.ps1']:
    copy(SOURCE/name,ARCHIVE/'source'/name)
shutil.copytree(OUT,ARCHIVE/'evidence/review')
shutil.copytree(ROOT/'docs/evidence/FPGA-优化04-仲裁路径-20261021',ARCHIVE/'evidence/implementation')
copy(ROOT/'docs/reviews/FPGA-事件仲裁优化效果审核-20261021-v0.1.md',ARCHIVE/'target/审核结论.md')
copy(ROOT/'README.md',ARCHIVE/'target/README.md')
receipt=json.loads((OUT/'debug8usb.receipt.json').read_text(encoding='utf-8-sig'))
copy(Path(receipt['Bitstream']),ARCHIVE/'target/debug8usb.fs')
assert sha(ARCHIVE/'target/debug8usb.fs')==receipt['BitstreamSha256']
(ARCHIVE/'MANIFEST.md').write_text('''# FPGA-20261021-v0.6

第四项事件仲裁优化审核，2026-10-21。source/ 是当前生产源文件、测试、ROM、约束和构建入口；target/ 是审核结论、项目说明和未烧录的 debug8usb 位流。evidence/review/ 为本轮输入/位流核对、短仿真、回退快照和清理记录；evidence/implementation/ 是原实现前后 PnR 与回归日志。REPRODUCE.md 提供复现入口，CHANGELOG.md 说明审核增量，checksums.sha256 校验除自身外的全部归档文件。

未改生产 RTL、未重复综合、未执行完整长门禁、未烧录。现有 Icarus、Gowin、Python 等运行环境保留。凭据中的绝对路径用于追溯原构建，迁移后需重建凭据。
''',encoding='utf-8')
(ARCHIVE/'CHANGELOG.md').write_text('''# 变更说明

审核确认第四项一拍事件暂存保留事件顺序、首键和清音语义，时序改善。新增短测试 tb_event_prefetch 并登记门禁：30 个预期事件通过，覆盖共享音高归属、满队列替换、连续 Note On/Off、Panic/模式取消暂存事件。更正原说明中 Logic 与 Register 混算、约束变化和瓶颈消失等不准确表述。

同 profile Fmax 31.938→39.408MHz，setup +5.727→+11.662ns。Logic +131，Register +16，BSRAM 40/46 与 DSP 1.75/24 不变。现有 222 输入、摘要、位流与工具版本全部匹配，没有重复综合。正式 standard27 PnR 和实体外设不在本轮验证范围。
''',encoding='utf-8')
(ARCHIVE/'REPRODUCE.md').write_text('''# 复现入口

已有结果足够支持审核，无需重复测试。需要复现时，在原项目工作区运行 evidence/review/commands/run_review.py，使用现有 Python 和 C:/iverilog/bin，只编译并运行 tb_event_prefetch；脚本定位最近的 Git 根及正式 source。归档 source 可用于恢复对应源码。运行后临时文件位于 tmp/event-review-20261021-v01，按明确清单清理。

commands/collect_build.py 只收集和核对现有成功构建。若更改 RTL，在 source/build 下运行 ./build.ps1 -Profile debug8usb -GwSh 'E:/Gowin/Gowin_V1.9.11.03_Education_x64/IDE/bin/gw_sh.exe' 重建。烧录前仍需执行项目完整仿真门禁。本轮未烧录。

evidence/review/audit_changes.patch 用于撤回本轮测试和门禁增量；before/top.v 为第三项完成时的顶层，fourth_item.patch 为第四项 RTL 增量。回退 RTL 后重新仿真、构建，不能继续使用当前凭据。
''',encoding='utf-8')
entries=sorted(p for p in ARCHIVE.rglob('*') if p.is_file())
lines=[sha(p)+'  '+p.relative_to(ARCHIVE).as_posix() for p in entries]
(ARCHIVE/'checksums.sha256').write_text('\n'.join(lines)+'\n',encoding='utf-8')
assert all(sha(ARCHIVE/line[66:])==line[:64] for line in lines)
print(f'Archive ready: {ARCHIVE}; {len(entries)} files verified; temporary directory removed.',flush=True)
