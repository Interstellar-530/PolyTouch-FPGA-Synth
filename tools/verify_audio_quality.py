"""Targeted full-scale headroom, analytic tuning and actual ADC reset checks."""
from pathlib import Path
import argparse,json,subprocess,sys,time

def main():
    sys.stdout.reconfigure(encoding='utf-8',errors='replace')
    parser=argparse.ArgumentParser();parser.add_argument('--out',type=Path);parser.add_argument('tests',nargs='*');args=parser.parse_args()
    root=Path(__file__).resolve().parents[1];source=root/'output/handoff_milestone2_20261008/source'
    work=root/'tmp/audio-quality-20261017';work.mkdir(parents=True,exist_ok=True)
    out=args.out or root/'docs/evidence/FPGA-音频质量-20261017-v0.1';out.mkdir(parents=True,exist_ok=True)
    result_file=out/'results.json'
    results=json.loads(result_file.read_text()) if args.tests and result_file.exists() else []
    tests=[('tb_headroom',None),('tb_bend_precision',None),('tb_adc_reset_top',1),('tb_adc_reset_top',0),('tb_control_sampling',1),('tb_control_sampling',0)]
    sources=list((source/'rtl/audio').glob('*.v'))+[source/'rtl/top.v',source/'sim/gowin_prom_model.v',source/'sim/mcp3208_model.v']
    for name,profile in tests:
        label=name if profile is None else name+('-standard' if profile else '-debug')
        if args.tests and label not in args.tests and name not in args.tests:continue
        exe=work/(label+'.vvp');started=time.monotonic()
        command=[r'C:\iverilog\bin\iverilog.exe','-g2012','-DSIMULATION','-I',str(source),'-s',name,'-o',str(exe)]
        if profile is not None:command+=['-P'+name+'.AUDIO_IF='+str(profile)]
        command += [str(source/'sim'/(name+'.v'))]+list(map(str,sources))
        cp=subprocess.run(command,cwd=source,capture_output=True)
        (out/(label+'-compile.log')).write_bytes(cp.stdout+cp.stderr)
        if cp.returncode:raise RuntimeError(cp.stderr.decode('utf-8','replace'))
        run=[r'C:\iverilog\bin\vvp.exe',str(exe)]
        if name=='tb_bend_precision':run+=['+CAPTURE='+str(work/'bend-precision.csv')]
        cp=subprocess.run(run,cwd=source,capture_output=True,timeout=150)
        (out/(label+'.log')).write_bytes(cp.stdout+cp.stderr)
        row=dict(test=label,exit=cp.returncode,seconds=round(time.monotonic()-started,3))
        results=[r for r in results if r['test']!=label]+[row]
        result_file.write_text(json.dumps(results,indent=2),encoding='utf-8')
        print(json.dumps(row),flush=True);print(cp.stdout.decode('utf-8','replace')[-1400:],flush=True)
        if cp.returncode:raise RuntimeError(label+' failed')
    if (work/'bend-precision.csv').exists():(out/'bend-precision.csv').write_bytes((work/'bend-precision.csv').read_bytes())

if __name__=='__main__':main()
