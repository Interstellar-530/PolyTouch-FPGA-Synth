"""Targeted timbre controls, UART, exact arithmetic and audio metric checks."""
from pathlib import Path
import argparse,csv,json,subprocess,sys,time
import numpy as np

def main():
    sys.stdout.reconfigure(encoding='utf-8',errors='replace')
    root=Path(__file__).resolve().parents[1]
    source=root/'source'
    work=root/'tmp/timbre-verification-20261016';work.mkdir(parents=True,exist_ok=True)
    parser=argparse.ArgumentParser();parser.add_argument('--out',type=Path);parser.add_argument('tests',nargs='*');args=parser.parse_args()
    out=args.out or root/'evidence/2026/10/FPGA-音色控制-20261016-v0.1';out.mkdir(parents=True,exist_ok=True)
    tests=['tb_timbre_controls','tb_timbre_audio','tb_timbre_uart','tb_timbre_top','tb_mode_uart','tb_poly','tb_pressure_top','tb_top_i2s']
    # Arguments optionally narrow the run for repairs, preserving other rows.
    only=args.tests
    results=json.loads((out/'results.json').read_text()) if only and (out/'results.json').exists() else []
    sources=list((source/'rtl/audio').glob('*.v'))+[source/'rtl/top.v']
    sources += [source/'sim'/name for name in ['gowin_prom_model.v','mcp3208_model.v','i2s_rx_model.v']]
    for name in tests:
        if only and name not in only:continue
        started=time.monotonic();exe=work/(name+'.vvp')
        command=[r'C:\iverilog\bin\iverilog.exe','-g2012','-DSIMULATION','-I',str(source),'-s',name,
                 '-o',str(exe),str(source/'sim'/(name+'.v'))]+list(map(str,sources))
        cp=subprocess.run(command,cwd=source,capture_output=True)
        (out/(name+'-compile.log')).write_bytes(cp.stdout+cp.stderr)
        if cp.returncode:raise RuntimeError(cp.stderr.decode('utf-8','replace'))
        run=[r'C:\iverilog\bin\vvp.exe',str(exe)]
        if name=='tb_timbre_audio':run+=['+CAPTURE='+str(work/'presets.csv')]
        cp=subprocess.run(run,cwd=source,capture_output=True,timeout=150)
        (out/(name+'.log')).write_bytes(cp.stdout+cp.stderr)
        row=dict(test=name,exit=cp.returncode,seconds=round(time.monotonic()-started,3))
        results=[r for r in results if r['test']!=name]+[row]
        (out/'results.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
        print(json.dumps(row),flush=True);print(cp.stdout.decode('utf-8','replace')[-1300:],flush=True)
        if cp.returncode:raise RuntimeError(name+' failed')
    capture=work/'presets.csv'
    if capture.exists():
        values=list(csv.DictReader(capture.open()))
        metrics=[]
        for weight in [0,64,160,255]:
            samples=np.array([int(r['sample']) for r in values if int(r['weight'])==weight],dtype=float)
            bins=np.abs(np.fft.rfft(samples))**2
            harmonic=np.sum(bins[2:17]);fundamental=bins[1]
            centroid=float(np.sum(np.arange(len(bins))*bins)/np.sum(bins))
            metrics.append(dict(weight=weight,samples=len(samples),rms=float(np.sqrt(np.mean(samples**2))),
                peak=float(np.max(np.abs(samples))),thd_percent=float(100*np.sqrt(harmonic/fundamental)),
                power_centroid_harmonic=centroid,clipped_samples=int(np.sum(np.abs(samples)>=32767))))
        assert all(metrics[i]['thd_percent']<metrics[i+1]['thd_percent'] for i in range(3))
        assert all(m['clipped_samples']==0 for m in metrics)
        (out/'spectral-metrics.json').write_text(json.dumps(metrics,indent=2),encoding='utf-8')
        (out/'presets.csv').write_bytes(capture.read_bytes())
        print(json.dumps(metrics),flush=True)
    print('Targeted verification complete; no full gate or hardware access.',flush=True)

if __name__=='__main__':main()
