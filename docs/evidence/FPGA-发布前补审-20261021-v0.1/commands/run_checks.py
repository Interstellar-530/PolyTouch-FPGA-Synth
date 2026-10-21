"""Targeted integration review; no full gate and no hardware programming."""
from pathlib import Path
import argparse,hashlib,json,subprocess
ROOT=next(p for p in Path(__file__).resolve().parents if (p/'.git').exists())
OUT=Path(__file__).resolve().parents[1];SRC=ROOT/'output/handoff_milestone2_20261008/source'
WORK=ROOT/'tmp/prepublish-review-20261021-v01';WORK.mkdir(parents=True,exist_ok=True)
p=argparse.ArgumentParser();p.add_argument('--before',action='store_true');a=p.parse_args();phase='before' if a.before else 'after'
roms=[SRC/'rtl/audio'/x for x in ['gowin_prom_piano_bank.v','gowin_prom_guitar_bank.v','gowin_prom_bright_bank.v']]
wrapper=(OUT/'before/rtl/prototypes/instrument_rom_banks.v') if a.before else SRC/'rtl/prototypes/instrument_rom_banks.v'
schedule=(OUT/'before/rtl/prototypes/voice_sched32.v') if a.before else SRC/'rtl/prototypes/voice_sched32.v'
cases=[('tb_instrument_rom_banks',[SRC/'sim/tb_instrument_rom_banks.v',wrapper,*roms,SRC/'sim/gowin_prom_model.v'],[]) ]
if a.before:
    cases += [('tb_voice_sched32_review',[SRC/'sim/tb_voice_sched32_review.v',schedule,SRC/'rtl/audio/note_phase_inc.v'],[f'+case={i}' for i in range(1,5)])]
else:
    cases += [('tb_voice_sched32_review',[SRC/'sim/tb_voice_sched32_review.v',schedule,SRC/'rtl/audio/note_phase_inc.v'],[]),
        ('tb_ram32_complete',[SRC/'sim/tb_ram32_complete.v',*sorted((SRC/'rtl/audio').glob('*.v')),
        *sorted((SRC/'rtl/prototypes').glob('*.v')),SRC/'sim/gowin_prom_model.v',SRC/'sim/i2s_rx_model.v'],[]),
        ('tb_ram_audio_datapath',[SRC/'sim/tb_ram_audio_datapath.v',*sorted((SRC/'rtl/audio').glob('*.v')),
        SRC/'sim/gowin_prom_model.v',SRC/'sim/i2s_rx_model.v'],[])]
rows=[];all_inputs={}
for name,inputs,args in cases:
    for path in inputs:all_inputs[str(path)]=hashlib.sha256(path.read_bytes()).hexdigest()
    binary=WORK/f'{name}_{phase}.vvp'
    commands=[('compile',['C:/iverilog/bin/iverilog.exe','-g2012','-DSIMULATION','-I','.', '-s',name,'-o',binary,*inputs])]
    commands += [(f'run{i+1}', ['C:/iverilog/bin/vvp.exe',binary,x]) for i,x in enumerate(args)] if args else [('run',['C:/iverilog/bin/vvp.exe',binary])]
    for step,cmd in commands:
        try:
            proc=subprocess.run([str(x) for x in cmd],cwd=SRC,capture_output=True,timeout=60);code=proc.returncode;data=proc.stdout+proc.stderr
        except subprocess.TimeoutExpired as e:code=124;data=(e.stdout or b'')+(e.stderr or b'')+b'\nTIMEOUT'
        (OUT/f'{phase}_{name}_{step}.log').write_bytes(data)
        expected=1 if a.before and step!='compile' else 0
        marker=(b'ROM_CE_hold_selected_wrong_group' if name=='tb_instrument_rom_banks' else b'FATAL:') if expected else b'PASS'
        ok=code==expected and (step=='compile' or marker in data)
        rows.append(dict(test=name,step=step,exit=code,expected=expected,passed=ok));print(phase,name,step,code,ok,flush=True)
        if step=='compile' and code:break
assert all(hashlib.sha256(Path(k).read_bytes()).hexdigest()==v for k,v in all_inputs.items()),'Inputs changed while testing'
result=dict(checks=rows,passed=all(r['passed'] for r in rows),inputs_sha256=all_inputs,full_gate=False,hardware_programmed=False)
(OUT/f'{phase}_results.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
raise SystemExit(0 if result['passed'] else 1)
