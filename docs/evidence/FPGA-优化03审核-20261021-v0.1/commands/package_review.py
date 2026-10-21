"""Archive this completed review, preserving sources, results and rollback patch."""
from pathlib import Path
import difflib, hashlib, json, shutil, subprocess

ROOT=next(p for p in Path(__file__).resolve().parents if (p/'.git').exists())
OUT=Path(__file__).resolve().parents[1]
REL=Path('output/handoff_milestone2_20261008/source')
SOURCE=ROOT/REL
ARCHIVE=ROOT/'archive/FPGA-20261021-v0.5'
assert not ARCHIVE.exists(), 'Never overwrite an existing archive'
def copy(src,dst):
    dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,dst)
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()

# A rollback patch for this review only, plus the full third-item change.
files=['rtl/audio/hid_keymap.v','rtl/audio/host_kbd_input.v','rtl/top.v',
       'sim/tb_host_kbd.v','sim/tb_top_host_ctrl.v','sim/run_simulation.ps1']
patch=[]
for name in ['rtl/audio/hid_keymap.v','sim/tb_host_kbd.v','sim/tb_top_host_ctrl.v','sim/run_simulation.ps1']:
    if name.startswith('rtl/'):
        old=(OUT/'before'/name[4:]).read_text(encoding='utf-8')
    elif name=='sim/tb_top_host_ctrl.v':
        old=(ROOT/'docs/evidence/FPGA-优化03-HID控制-20261021/tb_top_host_ctrl.v').read_text(encoding='utf-8-sig')
    else:
        old=subprocess.check_output(['git','show','HEAD:'+(REL/name).as_posix()],cwd=ROOT).decode('utf-8-sig')
        if name.endswith('run_simulation.ps1'):
            old=(SOURCE/name).read_text(encoding='utf-8-sig').replace(
                'F6 乐器切换、Up/Down 主音量','F6 音色预设、F7/F8 主音量')
    patch.extend(difflib.unified_diff(old.splitlines(True),(SOURCE/name).read_text(encoding='utf-8-sig').splitlines(True),
        fromfile='a/'+(REL/name).as_posix(),tofile='b/'+(REL/name).as_posix()))
(OUT/'review_fix.patch').write_text(''.join(patch),encoding='utf-8')
full=subprocess.check_output(['git','diff','HEAD','--',*[str(REL/x) for x in files]],cwd=ROOT)
# tb_top_host_ctrl is not yet tracked by Git, so include its complete source.
full+=(''.join(difflib.unified_diff([], (SOURCE/'sim/tb_top_host_ctrl.v').read_text(encoding='utf-8').splitlines(True),
    fromfile='/dev/null',tofile='b/'+(REL/'sim/tb_top_host_ctrl.v').as_posix()))).encode()
(OUT/'third_item.patch').write_bytes(full)

work=(ROOT/'tmp/hid-review-20261021-v01').resolve()
assert work.parent==(ROOT/'tmp').resolve()
expected={'tb_hid_repeat_review_after.vvp','tb_hid_repeat_review_before.vvp','tb_host_kbd_after.vvp','tb_top_host_ctrl_after.vvp'}
targets=list(work.iterdir())
assert {p.name for p in targets}==expected and all(p.is_file() and not p.is_symlink() for p in targets)
record=dict(archive=str(ARCHIVE),cleanup_targets=[str(p) for p in targets],cleanup_completed=False)
print('Cleanup targets: '+json.dumps(record['cleanup_targets'],ensure_ascii=False),flush=True)
for p in targets: p.unlink()
work.rmdir();record['cleanup_completed']=not work.exists()
(OUT/'packaging.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

ARCHIVE.mkdir(parents=True)
tracked=subprocess.check_output(['git','ls-files','-z','--',REL.as_posix()],cwd=ROOT).decode().split('\0')
for item in filter(None,tracked):
    p=ROOT/item
    if p.is_file(): copy(p,ARCHIVE/'source'/p.relative_to(SOURCE))
for item in ['sim/tb_top_host_ctrl.v','sim/tb_velocity_bounds.v','build/test_build_inputs.ps1']:
    copy(SOURCE/item,ARCHIVE/'source'/item)
for item in ['rtl/audio/hid_keymap.v','sim/tb_host_kbd.v','sim/tb_top_host_ctrl.v','sim/run_simulation.ps1']:
    assert (ARCHIVE/'source'/item).read_bytes()==(SOURCE/item).read_bytes()
shutil.copytree(OUT,ARCHIVE/'evidence/review')
shutil.copytree(ROOT/'docs/evidence/FPGA-优化03-HID控制-20261021',ARCHIVE/'evidence/implementation')
copy(ROOT/'docs/reviews/FPGA-HID控制优化效果审核-20261021-v0.1.md',ARCHIVE/'target/审核结论.md')
copy(ROOT/'README.md',ARCHIVE/'target/README.md')
receipt=json.loads((OUT/'debug8usb.receipt.json').read_text(encoding='utf-8-sig'))
copy(Path(receipt['Bitstream']),ARCHIVE/'target/debug8usb.fs')
assert sha(ARCHIVE/'target/debug8usb.fs')==receipt['BitstreamSha256']
(ARCHIVE/'MANIFEST.md').write_text('''# FPGA-20261021-v0.5

第三项 HID 控制效果审核及 F6 持键去重修正，2026-10-21。

source/ 为当前工程源文件、ROM、约束和可复现脚本快照；target/ 包含审核结论、当前项目说明和未烧录的 debug8usb.fs。evidence/review/ 保存修改前快照、前后短测试、修正补丁、成功构建凭据、报告与清理记录；evidence/implementation/ 为第三项原实现的历史证据。checksums.sha256 校验除其自身外全部归档文件。

依赖为现有 Icarus、Gowin 和 Python，未复制或删除这些运行环境。未执行完整长门禁、真实烧录或硬件验收。旧凭据中绝对路径用于追溯原构建，迁移归档后需重建生成新凭据。
''',encoding='utf-8')
(ARCHIVE/'CHANGELOG.md').write_text('''# 变更说明

修复 F6 引起 flush 后去重身份丢失，使同一个持键报告重复切换并重新起音的问题。普通清音保留最新物理键身份，清掉音符归属，松开后允许再次触发；断线及超时仍清空。补充现有顶层和键盘测试，修正门禁键位注释，更新当前资源/时序与原实现证据说明。

修改前独立复现失败；修正后 3 台短测试通过。1 次新构建通过，222 输入、摘要、位流及工具版本匹配。Logic 11537、寄存器 3689、BSRAM 40/46、DSP 1.75，Fmax 31.938MHz，setup +5.727ns、hold +0.319ns。回退使用 evidence/review/review_fix.patch 或 before/audio/hid_keymap.v，回退后重新仿真并构建。
''',encoding='utf-8')
(ARCHIVE/'REPRODUCE.md').write_text('''# 复现入口

无需重复现有检查。需要重现时，将 source 放回项目 source 位置，或在项目工作区使用 evidence/review/commands/run_review.py --phase after --top；脚本定位最近的 Git 项目根，依赖 C:/iverilog/bin。--phase before 使用保存的旧 keymap 复现失败。测试输出在项目 tmp/hid-review-20261021-v01，结束后按清单清理。

在 source/build 中运行 ./build.ps1 -Profile debug8usb -GwSh 'E:/Gowin/Gowin_V1.9.11.03_Education_x64/IDE/bin/gw_sh.exe' 构建；只使用提交的 ROM/HEX，不需下载素材。烧录前仍须执行项目要求的完整仿真门禁，本轮未烧录。
''',encoding='utf-8')
entries=sorted(p for p in ARCHIVE.rglob('*') if p.is_file())
lines=[sha(p)+'  '+p.relative_to(ARCHIVE).as_posix() for p in entries]
(ARCHIVE/'checksums.sha256').write_text('\n'.join(lines)+'\n',encoding='utf-8')
assert all(sha(ARCHIVE/line[66:])==line[:64] for line in lines)
print(f'Archive ready: {ARCHIVE}; {len(entries)} files verified; temporary directory removed.',flush=True)
