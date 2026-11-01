"""Bounded merge validation; unchanged production/prototype inputs are hashed."""
from pathlib import Path
import argparse,hashlib,json,subprocess
ROOT=next(p for p in Path(__file__).resolve().parents if (p/'.git').exists())
OUT=Path(__file__).resolve().parents[1];SRC=ROOT/'output/handoff_milestone2_20261008/source'
WORK=ROOT/'tmp/merge-review-20261022-v01';WORK.mkdir(parents=True,exist_ok=True)
p=argparse.ArgumentParser();p.add_argument('--before',action='store_true');a=p.parse_args();phase='before' if a.before else 'after'
names=['tb_generic_bright','tb_piano_engine','tb_piano_envelope','tb_piano_morph']
if not a.before:names+=['tb_velocity_bounds']
inputs={};rows=[]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
for name in names:
    tb=(OUT/'before/ours'/f'{name}.v') if a.before else SRC/'sim'/f'{name}.v'
    files=[tb,*sorted((SRC/'rtl/audio').glob('*.v')),SRC/'sim/gowin_prom_model.v']
    inputs.update({str(f):sha(f) for f in files})
    binary=WORK/f'{phase}_{name}.vvp'
    commands=[('compile',['C:/iverilog/bin/iverilog.exe','-g2012','-DSIMULATION','-I','.', '-s',name,'-o',str(binary),*[str(f) for f in files]]),
              ('run',['C:/iverilog/bin/vvp.exe',str(binary)])]
    for step,cmd in commands:
        try:
            r=subprocess.run(cmd,cwd=SRC,capture_output=True,timeout=45);code=r.returncode;data=r.stdout+r.stderr
        except subprocess.TimeoutExpired as e:code=124;data=(e.stdout or b'')+(e.stderr or b'')+b'\nTIMEOUT'
        (OUT/f'{phase}_{name}_{step}.log').write_bytes(data)
        ok=code==0 and (step=='compile' or b'PASS' in data)
        rows.append(dict(test=name,step=step,exit=code,passed=ok));print(phase,name,step,code,ok,flush=True)
        if step=='compile' and code:break
assert all(sha(Path(k))==v for k,v in inputs.items())
binding={}
if not a.before:
    prod=json.loads((ROOT/'docs/evidence/FPGA-优化05审核-20261021-v0.1/debug8usb.receipt.json').read_text(encoding='utf-8-sig'))
    assert all(sha(Path(x['Path']))==x['Sha256'] for x in prod['Inputs'])
    assert sha(ROOT/'releases/v2.1.0/debug8usb.fs')==prod['BitstreamSha256']
    proto=json.loads((ROOT/'docs/evidence/FPGA-发布前补审-20261021-v0.1/build_receipt.json').read_text(encoding='utf-8-sig'))
    assert all(sha(Path(k))==v for k,v in proto['inputs_sha256'].items())
    binding=dict(production_inputs=len(prod['Inputs']),prototype_inputs=len(proto['inputs_sha256']),production_bitstream_unchanged=True)
result=dict(checks=rows,all_passed=all(x['passed'] for x in rows),inputs_sha256=inputs,binding=binding,full_gate=False,hardware_programmed=False)
(OUT/f'{phase}_results.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8',newline='\n')
if not a.before:assert result['all_passed'],'Inspect logs before accepting the merge'
