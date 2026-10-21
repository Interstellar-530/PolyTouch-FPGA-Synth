"""Short checks of HID repeat handling, no hardware or full simulation gate."""
from pathlib import Path
import argparse, hashlib, json, subprocess

ROOT=next(p for p in Path(__file__).resolve().parents if (p/'.git').exists())
OUT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'output/handoff_milestone2_20261008/source'
WORK=ROOT/'tmp/hid-review-20261021-v01'

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--phase',choices=['before','after'],required=True)
    parser.add_argument('--top',action='store_true');args=parser.parse_args()
    WORK.mkdir(parents=True,exist_ok=True)
    if args.phase=='before':
        for name in ['audio/hid_keymap.v','audio/host_kbd_input.v','top.v']:
            dst=OUT/'before'/name;dst.parent.mkdir(parents=True,exist_ok=True)
            if not dst.exists():
                dst.write_bytes((SOURCE/'rtl'/name).read_bytes())
    keymap=(OUT/'before/audio/hid_keymap.v') if args.phase=='before' else (SOURCE/'rtl/audio/hid_keymap.v')
    cases=[('tb_hid_repeat_review',OUT/'source/tb_hid_repeat_review.v',[keymap])]
    if args.top:
        inputs=sorted((SOURCE/'rtl/audio').glob('*.v'))+[SOURCE/'rtl/top.v',SOURCE/'sim/gowin_prom_model.v',SOURCE/'sim/mcp3208_model.v']
        cases += [('tb_top_host_ctrl',SOURCE/'sim/tb_top_host_ctrl.v',inputs),
                  ('tb_host_kbd',SOURCE/'sim/tb_host_kbd.v',inputs)]
    rows=[]
    for name,bench,inputs in cases:
        binary=WORK/f'{name}_{args.phase}.vvp'
        commands=[('compile',['C:/iverilog/bin/iverilog.exe','-g2012','-DSIMULATION','-I','.', '-s',name,'-o',binary,bench,*inputs]),
                  ('run',['C:/iverilog/bin/vvp.exe',binary])]
        for step,cmd in commands:
            try:
                result=subprocess.run([str(x) for x in cmd],cwd=SOURCE,capture_output=True,timeout=60)
                data=result.stdout+result.stderr;code=result.returncode
            except subprocess.TimeoutExpired as error:
                data=(error.stdout or b'')+(error.stderr or b'')+b'\nTIMEOUT\n';code=124
            (OUT/f'{name}_{args.phase}_{step}.log').write_bytes(data)
            expected=1 if args.phase=='before' and step=='run' else 0
            passed=code==expected and (step=='compile' or (b'held F6 report retriggered' in data if expected else b'PASS' in data))
            rows.append(dict(check=name+'_'+step,exit=code,expected_exit=expected,passed=passed))
            print(f'{args.phase} {name} {step}: exit={code} accepted={passed}',flush=True)
            if code!=0 and step=='compile':break
    hashes={name:hashlib.sha256((SOURCE/name).read_bytes()).hexdigest() for name in
            ['rtl/audio/hid_keymap.v','rtl/audio/host_kbd_input.v','rtl/top.v','sim/tb_top_host_ctrl.v','sim/tb_host_kbd.v']}
    hashes['tested_keymap']=hashlib.sha256(keymap.read_bytes()).hexdigest()
    result=dict(phase=args.phase,checks=rows,passed=all(x['passed'] for x in rows),inputs_sha256=hashes,
                full_gate=False,hardware_programmed=False)
    (OUT/f'{args.phase}_results.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    raise SystemExit(0 if result['passed'] else 1)

if __name__=='__main__':main()
