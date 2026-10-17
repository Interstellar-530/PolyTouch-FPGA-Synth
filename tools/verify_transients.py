"""Directed de-click tests and reproducible digital transition metrics."""
from pathlib import Path
import argparse,csv,json,subprocess,sys,time
import numpy as np

def main():
    sys.stdout.reconfigure(encoding='utf-8',errors='replace')
    parser=argparse.ArgumentParser();parser.add_argument('--out',type=Path);parser.add_argument('--analyze-only',action='store_true');parser.add_argument('tests',nargs='*');args=parser.parse_args()
    root=Path(__file__).resolve().parents[1];source=root/'output/handoff_milestone2_20261008/source'
    work=root/'tmp/transients-20261017';work.mkdir(parents=True,exist_ok=True)
    out=args.out or root/'docs/evidence/FPGA-静音过渡-20261017-v0.1';out.mkdir(parents=True,exist_ok=True)
    results=json.loads((out/'results.json').read_text()) if args.analyze_only and (out/'results.json').exists() else []
    for name in args.tests or ['tb_mute_slew']:
        started=time.monotonic();exe=work/(name+'.vvp')
        sources=list((source/'rtl/audio').glob('*.v'))+[source/'rtl/top.v',source/'sim/gowin_prom_model.v',source/'sim/mcp3208_model.v',source/'sim/i2s_rx_model.v']
        cmd=[r'C:\iverilog\bin\iverilog.exe','-g2012','-DSIMULATION','-I',str(source),'-s',name,'-o',str(exe),str(source/'sim'/(name+'.v'))]+list(map(str,sources))
        capture=(out if args.analyze_only else work)/(name+'.csv')
        if not args.analyze_only:
            cp=subprocess.run(cmd,cwd=source,capture_output=True);(out/(name+'-compile.log')).write_bytes(cp.stdout+cp.stderr)
            if cp.returncode:raise RuntimeError(cp.stderr.decode('utf-8','replace'))
            cp=subprocess.run([r'C:\iverilog\bin\vvp.exe',str(exe),'+CAPTURE='+str(capture)],cwd=source,capture_output=True,timeout=300)
            (out/(name+'.log')).write_bytes(cp.stdout+cp.stderr)
            results.append(dict(test=name,exit=cp.returncode,seconds=round(time.monotonic()-started,3)))
            (out/'results.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
            print(cp.stdout.decode('utf-8','replace')[-1800:],flush=True)
            if cp.returncode:raise RuntimeError(name+' failed')
        if capture.exists():(out/capture.name).write_bytes(capture.read_bytes())
        if name=='tb_precision_audio':
            rows=list(csv.DictReader(capture.open()));wave=np.array([int(x,16) for x in (source/'rtl/audio/wave_sine.hex').read_text().split()]);wave=np.where(wave>=32768,wave-65536,wave)
            coefficient=np.fft.rfft(wave)[1]/512
            metrics=[]
            for case_id in range(8):
                group=[r for r in rows if int(r['case_id'])==case_id]
                phase=np.array([int(r['phase']) for r in group],dtype=float)/2**32
                ideal=2*np.real(coefficient*np.exp(2j*np.pi*phase))*int(group[0]['env'])/65536*100/128*255/256/4*int(group[0]['gain'])/4096*256
                snrs={}
                for key in ['legacy','wide']:
                    signal=np.array([int(r[key]) for r in group],dtype=float)
                    snrs[key]=float(10*np.log10(np.mean(ideal**2)/np.mean((signal-ideal)**2)))
                metric=dict(case_id=case_id,envelope=int(group[0]['env']),gain_q12=int(group[0]['gain']),legacy_snr_db=snrs['legacy'],wide_snr_db=snrs['wide'],improvement_db=snrs['wide']-snrs['legacy'])
                assert metric['improvement_db']>8
                if case_id==0:assert metric['wide_snr_db']>=92
                metrics.append(metric)
            (out/'precision-metrics.json').write_text(json.dumps(metrics,indent=2),encoding='utf-8');print(json.dumps(metrics),flush=True)
        if name=='tb_mute_slew':
            rows=list(csv.DictReader(capture.open()));soft=np.array([int(r['smooth']) for r in rows[:192]],dtype=float);hard=np.array([int(r['hard']) for r in rows[:192]],dtype=float)
            ds=np.diff(soft);dh=np.diff(hard);freq=np.fft.rfftfreq(16384,1/48000);band=(freq>=5000)&(freq<=20000)
            ratio=np.sum(abs(np.fft.rfft(ds,16384)[band])**2)/np.sum(abs(np.fft.rfft(dh,16384)[band])**2)
            metrics=dict(stimulus='constant 24902 LSB, unity-to-zero transition; derivative spectrum',ramp_frames=128,ramp_ms=128/48,max_step_smooth=float(max(abs(ds))),max_step_hard=float(max(abs(dh))),high_band_energy_reduction_db=float(-10*np.log10(ratio)))
            assert metrics['high_band_energy_reduction_db']>20
            (out/'mute-metrics.json').write_text(json.dumps(metrics,indent=2),encoding='utf-8');print(json.dumps(metrics),flush=True)
        if name=='tb_voice_transition_audio':
            rows=list(csv.DictReader(capture.open()));cases=[];soft_energy=0.;hard_energy=0.
            freq=np.fft.rfftfreq(16384,1/48000);band=(freq>=5000)&(freq<=20000)
            for case_id in range(16):
                group=[r for r in rows if int(r['case_id'])==case_id]
                soft=np.array([int(r['soft']) for r in group],dtype=float);hard=np.array([int(r['hard']) for r in group],dtype=float)
                window=np.hanning(len(soft)-1)
                es=float(np.sum(abs(np.fft.rfft(np.diff(soft)*window,16384)[band])**2))
                eh=float(np.sum(abs(np.fft.rfft(np.diff(hard)*window,16384)[band])**2))
                soft_energy+=es;hard_energy+=eh
                cases.append(dict(case_id=case_id,weight=int(group[0]['weight']),high_band_reduction_db=float(10*np.log10(eh/es))))
            metrics=dict(stimulus='actual sine C4-to-E4 and bright C3-to-G3, eight phase offsets each; Hann-windowed derivative spectrum',cases=cases,captured_frames=len(rows),aggregate_high_band_reduction_db=float(10*np.log10(hard_energy/soft_energy)),max_extra_delay_ms=64/48)
            assert metrics['aggregate_high_band_reduction_db']>=20
            (out/'voice-metrics.json').write_text(json.dumps(metrics,indent=2),encoding='utf-8');print(json.dumps(metrics),flush=True)

if __name__=='__main__':main()
