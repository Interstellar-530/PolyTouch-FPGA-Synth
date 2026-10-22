"""Snapshot the reviewed merge and remove its exact simulation temp directory."""
from pathlib import Path
import hashlib,json,shutil,subprocess
ROOT=next(p for p in Path(__file__).resolve().parents if (p/'.git').exists())
OUT=Path(__file__).resolve().parents[1];REL=Path('output/handoff_milestone2_20261008/source');SRC=ROOT/REL
A=ROOT/'archive/FPGA-20261022-v0.1';WORK=ROOT/'tmp/merge-review-20261022-v01'
assert not A.exists(),'Never overwrite archives'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def copy(a,b):b.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(a,b)
def write(p,s):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(s,encoding='utf-8',newline='\n')
result=json.loads((OUT/'after_results.json').read_text())
assert result['all_passed'] and all(sha(Path(k))==v for k,v in result['inputs_sha256'].items())
assert WORK.resolve().parent==(ROOT/'tmp').resolve() and not WORK.is_symlink() and not WORK.is_junction()
paths=list(WORK.rglob('*'))
assert all(p.resolve().is_relative_to(WORK.resolve()) and p.is_file() and p.suffix=='.vvp' for p in paths)
write(OUT/'cleanup_inventory.json',json.dumps(dict(root=str(WORK.resolve()),files=[str(p.relative_to(WORK)) for p in paths]),indent=2)+'\n')
print('Cleanup target: '+str(WORK.resolve())+'; files='+str(len(paths)),flush=True)
shutil.rmtree(WORK);assert not WORK.exists()
changed=subprocess.check_output(['git','diff','HEAD','--name-only','--',str(REL/'rtl'),str(REL/'constraints'),str(REL/'build')],cwd=ROOT)
assert not changed,'Production/prototype implementation changed unexpectedly'
write(OUT/'packaging.json',json.dumps(dict(archive=str(A),temporary_directory_removed=True,rtl_constraints_build_unchanged=True,
    tests_passed=5,full_gate=False,hardware_programmed=False,remote_pushed=False),indent=2)+'\n')
files=subprocess.check_output(['git','ls-files','-c','-o','--exclude-standard','-z','--',REL.as_posix()],cwd=ROOT).decode().split('\0')
for name in sorted(set(filter(None,files))):
    p=ROOT/name
    if p.is_file():copy(p,A/'source'/p.relative_to(SRC))
for name in ['gen_epiano_bank.py','gen_piano_prom.py','gen_guitar_bank.py','gen_guitar_samples_bank.py','verify_build_profiles.py','render_bank_ab.py']:
    copy(ROOT/'tools'/name,A/'tools'/name)
shutil.copytree(OUT,A/'evidence')
copy(ROOT/'releases/v2.1.0/debug8usb.fs',A/'target/debug8usb-v2.1.0-unchanged.fs')
copy(ROOT/'docs/reviews/FPGA-队友版本合流评审-20261022-v0.1.md',A/'target/合流评审.md')
copy(ROOT/'docs/releases/v2.1.1.md',A/'CHANGELOG.md')
copy(ROOT/'README.md',A/'target/README.md')
for k,v in result['inputs_sha256'].items():
    p=Path(k)
    if p.is_relative_to(SRC):assert sha(A/'source'/p.relative_to(SRC))==v
write(A/'MANIFEST.md','''# FPGA-20261022-v0.1

v2.1.1 本地合流基线，保留 v2.1.0 与队友 f7052fb 的历史和优点。source/ 为完整工程、测试、波表和构建配置；tools/ 为已有相关工具；target/ 为原样沿用的生产位流、项目说明与合流评审；evidence/ 为双方原始测试、修改依据、前后仿真、输入绑定与清理清单。CHANGELOG.md 为最终变更说明。

仅四个测试台改变，生产/原型实现、位流及音频数据不变，没有增加硬件资源。五个定向测试通过，192 个生产输入、21 个原型输入保持匹配。未运行完整长门禁、未烧录、未推送。checksums.sha256 覆盖归档原始字节；换行转换后重新生成构建凭据。
''')
write(A/'REPRODUCE.md','''# 复现

从项目 Git 根运行 python -B docs/evidence/FPGA-版本合流-20261022-v0.1/commands/run_checks.py。--before 使用 evidence/before/ours 的旧测试，不改变生产 RTL；默认验证四个合流测试及 0..255 力度边界，需 C:/iverilog/bin 和 Python。已有日志足够支持本次合流，无需再次运行。

归档 source/ 可按原 output/handoff_milestone2_20261008/source 层级恢复；普通生产构建按项目 README 调用 build/build.ps1。正式烧录前仍运行完整 run_simulation.ps1。v2.0.0→v2.1.0 与 v2.0.0→f7052fb 分别保留在 Git 历史，v2.1.0 可回退。
''')
entries=sorted(p for p in A.rglob('*') if p.is_file())
lines=[sha(p)+'  '+p.relative_to(A).as_posix() for p in entries]
write(A/'checksums.sha256','\n'.join(lines)+'\n')
assert all(sha(A/line[66:])==line[:64] for line in lines)
print('Archive ready: '+str(A)+'; '+str(len(entries))+' files SHA256 verified.')
