"""Targeted FSR verification. Does not run the programming gate or hardware."""
from pathlib import Path
import argparse,json,subprocess,sys,time


def main():
    sys.stdout.reconfigure(encoding='utf-8',errors='replace')
    parser=argparse.ArgumentParser()
    parser.add_argument('--only',nargs='+')
    parser.add_argument('--iverilog',default=r'C:\iverilog\bin\iverilog.exe')
    parser.add_argument('--vvp',default=r'C:\iverilog\bin\vvp.exe')
    parser.add_argument('--source',type=Path)
    parser.add_argument('--out',type=Path)
    args=parser.parse_args()
    root=Path(__file__).resolve().parents[1]
    source=(args.source or root/'output/handoff_milestone2_20261008/source').resolve()
    out=(args.out or root/'docs/evidence/FPGA-FSR音量-20261016-v0.1').resolve()
    build=root/'tmp/pressure-verification-20261016';build.mkdir(parents=True,exist_ok=True)
    out.mkdir(parents=True,exist_ok=True)
    tests=['tb_pressure_gain','tb_pressure_top','tb_pressure_bend','tb_shared_engine','tb_top_i2s']
    src=list((source/'rtl/audio').glob('*.v'))+[source/'rtl/top.v',
       source/'sim/gowin_prom_model.v',source/'sim/mcp3208_model.v',source/'sim/i2s_rx_model.v']
    result_file=out/'results.json'
    results=json.loads(result_file.read_text(encoding='utf-8')) if args.only and result_file.exists() else []
    for name in tests:
        if args.only and name not in args.only:continue
        exe=build/(name+'.vvp')
        command=[args.iverilog,'-g2012','-DSIMULATION','-I',str(source),'-s',name,
          '-o',str(exe),str(source/'sim'/(name+'.v'))]+list(map(str,src))
        started=time.monotonic()
        cp=subprocess.run(command,cwd=source,capture_output=True)
        (out/(name+'-compile.log')).write_bytes(cp.stdout+cp.stderr)
        run=None
        if cp.returncode==0:
            run=subprocess.run([args.vvp,str(exe)],cwd=source,capture_output=True,timeout=180)
            (out/(name+'.log')).write_bytes(run.stdout+run.stderr)
        row=dict(test=name,compile_exit=cp.returncode,simulation_exit=run.returncode if run else None,
          seconds=round(time.monotonic()-started,3),command=command,cwd=str(source))
        results=[x for x in results if x['test']!=name]+[row]
        result_file.write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8')
        print(json.dumps({k:v for k,v in row.items() if k not in ('command','cwd')},ensure_ascii=False),flush=True)
        if run:print(run.stdout.decode('utf-8','replace')[-1800:],flush=True)
    return int(any(x['compile_exit']!=0 or x['simulation_exit']!=0 for x in results))


if __name__=='__main__':raise SystemExit(main())
