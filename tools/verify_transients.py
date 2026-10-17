"""Directed de-click tests and reproducible digital transition metrics."""
from pathlib import Path
import argparse,csv,json,subprocess,sys,time
import numpy as np

def main():
    sys.stdout.reconfigure(encoding='utf-8',errors='replace')
    parser=argparse.ArgumentParser();parser.add_argument('--out',type=Path);parser.add_argument('tests',nargs='*');args=parser.parse_args()
    root=Path(__file__).resolve().parents[1];source=root/'output/handoff_milestone2_20261008/source'
    work=root/'tmp/transients-20261017';work.mkdir(parents=True,exist_ok=True)
    out=args.out or root/'docs/evidence/FPGA-静音过渡-20261017-v0.1';out.mkdir(parents=True,exist_ok=True)
    results=[]
    for name in args.tests or ['tb_mute_slew']:
        started=time.monotonic();exe=work/(name+'.vvp')
        sources=list((source/'rtl/audio').glob('*.v'))+[source/'rtl/top.v',source/'sim/gowin_prom_model.v',source/'sim/mcp3208_model.v',source/'sim/i2s_rx_model.v']
        cmd=[r'C:\iverilog\bin\iverilog.exe','-g2012','-DSIMULATION','-I',str(source),'-s',name,'-o',str(exe),str(source/'sim'/(name+'.v'))]+list(map(str,sources))
        cp=subprocess.run(cmd,cwd=source,capture_output=True);(out/(name+'-compile.log')).write_bytes(cp.stdout+cp.stderr)
        if cp.returncode:raise RuntimeError(cp.stderr.decode('utf-8','replace'))
        capture=work/(name+'.csv')
        cp=subprocess.run([r'C:\iverilog\bin\vvp.exe',str(exe),'+CAPTURE='+str(capture)],cwd=source,capture_output=True,timeout=150)
        (out/(name+'.log')).write_bytes(cp.stdout+cp.stderr)
        results.append(dict(test=name,exit=cp.returncode,seconds=round(time.monotonic()-started,3)))
        (out/'results.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
        print(cp.stdout.decode('utf-8','replace')[-1800:],flush=True)
        if cp.returncode:raise RuntimeError(name+' failed')
        if capture.exists():(out/capture.name).write_bytes(capture.read_bytes())
        if name=='tb_mute_slew':
            rows=list(csv.DictReader(capture.open()));soft=np.array([int(r['smooth']) for r in rows[:192]],dtype=float);hard=np.array([int(r['hard']) for r in rows[:192]],dtype=float)
            ds=np.diff(soft);dh=np.diff(hard);freq=np.fft.rfftfreq(16384,1/48000);band=(freq>=5000)&(freq<=20000)
            ratio=np.sum(abs(np.fft.rfft(ds,16384)[band])**2)/np.sum(abs(np.fft.rfft(dh,16384)[band])**2)
            metrics=dict(stimulus='constant 24902 LSB, unity-to-zero transition; derivative spectrum',ramp_frames=128,ramp_ms=128/48,max_step_smooth=float(max(abs(ds))),max_step_hard=float(max(abs(dh))),high_band_energy_reduction_db=float(-10*np.log10(ratio)))
            assert metrics['high_band_energy_reduction_db']>20
            (out/'mute-metrics.json').write_text(json.dumps(metrics,indent=2),encoding='utf-8');print(json.dumps(metrics),flush=True)

if __name__=='__main__':main()
