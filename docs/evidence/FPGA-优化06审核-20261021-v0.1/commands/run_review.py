"""Short scheduler failure reproductions and corrected full-path regression."""
from pathlib import Path
import argparse,hashlib,json,subprocess,shutil
ROOT=next(p for p in Path(__file__).resolve().parents if (p/'.git').exists())
OUT=Path(__file__).resolve().parents[1];SRC=ROOT/'output/handoff_milestone2_20261008/source'
WORK=ROOT/'tmp/ram32-review-20261021-v01';WORK.mkdir(parents=True,exist_ok=True)
p=argparse.ArgumentParser();p.add_argument('--phase',choices=['before','after'],required=True);p.add_argument('--default-only',action='store_true');a=p.parse_args()
if a.phase=='before':
    for name in ['rtl/prototypes/voice_sched32.v','rtl/prototypes/ram32_top.v','sim/tb_ram32_complete.v','sim/run_simulation.ps1']:
        dst=OUT/'before'/name;dst.parent.mkdir(parents=True,exist_ok=True)
        if not dst.exists():shutil.copy2(SRC/name,dst)
sched=(OUT/'before/rtl/prototypes/voice_sched32.v') if a.phase=='before' else SRC/'rtl/prototypes/voice_sched32.v'
rows=[]
def run(name,cmd,expected=0,marker=None):
    try:
        r=subprocess.run([str(x) for x in cmd],cwd=SRC,capture_output=True,timeout=60);code=r.returncode;data=r.stdout+r.stderr
    except subprocess.TimeoutExpired as e:code=124;data=(e.stdout or b'')+(e.stderr or b'')+b'\nTIMEOUT'
    (OUT/f'{a.phase}_{name}.log').write_bytes(data)
    passed=code==expected and (marker is None or marker.encode() in data)
    rows.append(dict(check=name,exit=code,expected_exit=expected,passed=passed))
    print(a.phase,name,code,passed,flush=True);return passed
iv='C:/iverilog/bin/iverilog.exe';vv='C:/iverilog/bin/vvp.exe'
binary=WORK/f'scheduler_{a.phase}.vvp'
if run('scheduler_compile',[iv,'-g2012','-DSIMULATION','-I','.', '-s','tb_voice_sched32_review','-o',binary,
                          SRC/'sim/tb_voice_sched32_review.v',sched,SRC/'rtl/audio/note_phase_inc.v']):
    if a.default_only:
        run('scheduler_gate_default',[vv,binary],marker='PASS tb_voice_sched32_review case=4')
    else:
        for case,marker in enumerate(['queued_note_corrupted_retrigger','age_wrap_wrong_steal','config_dropped_under_backpressure','velocity_truncated_to_silence'],1):
            run(f'scheduler_case{case}',[vv,binary,f'+case={case}'],1 if a.phase=='before' else 0,
                marker if a.phase=='before' else 'PASS tb_voice_sched32_review')
if a.phase=='after' and not a.default_only:
    binary=WORK/'complete_after.vvp'
    sources=[SRC/x for x in ['rtl/prototypes/ram32_top.v','rtl/prototypes/voice_sched32.v',
        'rtl/audio/ram_audio_datapath.v','rtl/audio/ram_audio_compute.v','rtl/audio/ram_wavetable_engine.v',
        'rtl/audio/voice_state_ram.v','rtl/audio/note_phase_inc.v','rtl/audio/wide_master.v','rtl/audio/i2s_tx.v',
        'rtl/audio/split_audio_multiplier.v','rtl/audio/gowin_prom_wave_sine.v','rtl/audio/gowin_prom_bright_bank.v',
        'sim/gowin_prom_model.v','sim/i2s_rx_model.v','sim/tb_ram32_complete.v']]
    if run('complete_compile',[iv,'-g2012','-DSIMULATION','-I','.', '-s','tb_ram32_complete','-o',binary,*sources]):
        run('complete_run',[vv,binary],marker='PASS tb_ram32_complete')
result=dict(phase=a.phase,checks=rows,passed=all(r['passed'] for r in rows),full_gate=False,hardware_programmed=False,
    scheduler_sha256=hashlib.sha256(sched.read_bytes()).hexdigest())
(OUT/f'{a.phase}{"_gate_default" if a.default_only else ""}_results.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
raise SystemExit(0 if result['passed'] else 1)
