"""Frame equivalence against preserved prior RTL; no full gate or hardware."""
from pathlib import Path
import argparse,json,subprocess,sys,time

def main():
    sys.stdout.reconfigure(encoding='utf-8',errors='replace')
    root=Path(__file__).resolve().parents[1];source=root/'output/handoff_milestone2_20261008/source'
    parser=argparse.ArgumentParser();parser.add_argument('--out',type=Path);parser.add_argument('tests',nargs='*');args=parser.parse_args()
    work=root/'tmp/architecture-verification-20261016';work.mkdir(parents=True,exist_ok=True)
    out=args.out or root/'docs/evidence/FPGA-架构优化-20261016-v0.1';out.mkdir(parents=True,exist_ok=True)
    results=[]
    for name in args.tests or ['tb_architecture_equivalence','tb_shared_bend_equivalence','tb_bend_equivalence','tb_shared_master','tb_frame_velocity']:
        started=time.monotonic();exe=work/(name+'.vvp')
        sources=list((source/'rtl/audio').glob('*.v'))+list((source/'sim/reference').glob('baseline_*.v'))+[source/'sim/gowin_prom_model.v']
        cmd=[r'C:\iverilog\bin\iverilog.exe','-g2012','-DSIMULATION','-I',str(source),'-s',name,'-o',str(exe),str(source/'sim'/(name+'.v'))]+list(map(str,sources))
        cp=subprocess.run(cmd,cwd=source,capture_output=True);(out/(name+'-compile.log')).write_bytes(cp.stdout+cp.stderr)
        if cp.returncode:raise RuntimeError(cp.stderr.decode('utf-8','replace'))
        cp=subprocess.run([r'C:\iverilog\bin\vvp.exe',str(exe)],cwd=source,capture_output=True,timeout=150)
        (out/(name+'.log')).write_bytes(cp.stdout+cp.stderr)
        results.append(dict(test=name,exit=cp.returncode,seconds=round(time.monotonic()-started,3)))
        (out/'results.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
        print(json.dumps(results[-1]),flush=True);print(cp.stdout.decode('utf-8','replace')[-1500:],flush=True)
        if cp.returncode:raise RuntimeError(name+' failed')

if __name__=='__main__':main()
