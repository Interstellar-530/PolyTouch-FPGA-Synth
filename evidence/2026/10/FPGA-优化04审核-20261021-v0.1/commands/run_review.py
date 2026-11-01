"""One short control-path integration check, no full gate or hardware."""
from pathlib import Path
import hashlib,json,subprocess
ROOT=next(p for p in Path(__file__).resolve().parents if (p/'.git').exists())
OUT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'output/handoff_milestone2_20261008/source'
WORK=ROOT/'tmp/event-review-20261021-v01'
WORK.mkdir(parents=True,exist_ok=True)
binary=WORK/'tb_event_prefetch.vvp'
inputs=[SOURCE/'sim/tb_event_prefetch.v',*sorted((SOURCE/'rtl/audio').glob('*.v')),
        SOURCE/'rtl/top.v',SOURCE/'sim/gowin_prom_model.v']
commands=[('compile',['C:/iverilog/bin/iverilog.exe','-g2012','-DSIMULATION','-I','.',
                     '-s','tb_event_prefetch','-o',binary,*inputs]),
          ('run',['C:/iverilog/bin/vvp.exe',binary])]
checks=[]
for name,cmd in commands:
    try:
        p=subprocess.run([str(x) for x in cmd],cwd=SOURCE,capture_output=True,timeout=60)
        data=p.stdout+p.stderr;code=p.returncode
    except subprocess.TimeoutExpired as e:
        data=(e.stdout or b'')+(e.stderr or b'')+b'\nTIMEOUT';code=124
    (OUT/f'tb_event_prefetch_{name}.log').write_bytes(data)
    passed=code==0 and (name=='compile' or b'PASS tb_event_prefetch' in data)
    checks.append(dict(step=name,exit=code,passed=passed))
    print(f'{name}: exit={code} passed={passed}',flush=True)
    if not passed:break
result=dict(checks=checks,passed=len(checks)==2 and all(x['passed'] for x in checks),
            inputs_sha256={str(p.relative_to(SOURCE)):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs},
            full_gate=False,hardware_programmed=False)
(OUT/'simulation_results.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
raise SystemExit(0 if result['passed'] else 1)
