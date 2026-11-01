"""One post-fix prototype PnR, with a content-bound receipt and saved reports."""
from pathlib import Path
import hashlib,json,os,re,shutil,subprocess
ROOT=next(p for p in Path(__file__).resolve().parents if (p/'.git').exists())
OUT=Path(__file__).resolve().parents[1];SRC=ROOT/'output/handoff_milestone2_20261008/source'
WORK=ROOT/'tmp/ram32-review-pnr-20261021-v01'
assert not WORK.exists(),'Use a fresh reviewed build directory'
WORK.mkdir(parents=True)
tcl=SRC/'build/ram32_proto.tcl'
block=re.search(r'set sources \{(.*?)\}',tcl.read_text(),re.S)[1]
inputs=[SRC/x for x in block.split()]+[tcl,SRC/'constraints/ram32_proto.sdc',*sorted((SRC/'rtl/audio').glob('*.vh'))]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
before={str(p):sha(p) for p in inputs}
env=os.environ.copy();env['FPGA_BUILD_RUN_DIR']=str(WORK)
tool=Path('E:/Gowin/Gowin_V1.9.11.03_Education_x64/IDE/bin/gw_sh.exe')
print('Building corrected standalone RAM32 prototype',flush=True)
with (OUT/'build_after.log').open('wb') as log:
    r=subprocess.run([str(tool),str(tcl)],cwd=ROOT,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=240)
after={str(p):sha(p) for p in inputs}
assert r.returncode==0 and before==after,'Build failed or inputs changed'
pnr=WORK/'ram32/impl/pnr';fs=pnr/'ram32.fs'
assert fs.is_file() and fs.stat().st_size>0
reports=OUT/'build_reports';reports.mkdir(exist_ok=True)
for name in ['ram32.rpt.txt','ram32_tr_content.html','ram32.pin.html']:
    shutil.copy2(pnr/name,reports/name)
shutil.copy2(fs,OUT/'ram32.fs')
receipt=dict(target='standalone ram32_top',product_profile=False,tool=str(tool),
    tool_version=re.search(r'<Tool Version>:\s*(.+)',(pnr/'ram32.rpt.txt').read_text())[1].strip(),
    inputs_sha256=before,inputs_unchanged=True,bitstream=str(OUT/'ram32.fs'),bitstream_sha256=sha(fs),
    original_build=str(WORK),hardware_programmed=False,pins_constrained=False,clock_generated=False)
(OUT/'build_receipt.json').write_text(json.dumps(receipt,indent=2)+'\n',encoding='utf-8')
print(f'Build passed; {len(inputs)} inputs unchanged; reports and bitstream retained.',flush=True)
