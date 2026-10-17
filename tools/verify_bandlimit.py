"""Independent integer oracle, ROM tests and coherent alias measurements."""
from pathlib import Path
import argparse,csv,json,subprocess,random,sys
import numpy as np

ROOT=Path(__file__).resolve().parents[1]
SRC=ROOT/'output/handoff_milestone2_20261008/source'
def load(name):
    a=[int(x,16) for x in (SRC/'rtl/audio'/name).read_text().split()]
    return [x-65536 if x>=32768 else x for x in a]
def config(inc):
    for k in range(4):
        if inc < 1<<(27+k):
            return k,max(0,(inc-(1<<(26+k)))>>(10+k))
    return 4,0
def interp(table,p):
    a=p>>23;f=(p>>14)&511
    return table[a]+((table[(a+1)&511]-table[a])*f+256>>9)
def vectors(path,smoke=False):
    sine=load('wave_sine.hex');banks=[load(f'wave_bright_h{h}.hex') for h in [16,8,4,2,1]]
    phases=[0]*4;randoms=random.Random(20261017);rows=[];spec=[]
    def emit(incs,ratio,env,vel,retrig,case=-1):
        ss=0;bs=0
        for v in range(4):
            inc=(incs[v]*ratio>>16)&0xffffffff
            phases[v]=0 if retrig>>v&1 else (phases[v]+inc)&0xffffffff
            lo,w=config(inc);p=phases[v]
            a=interp(banks[lo],p);b=interp(banks[min(lo+1,4)],p)
            s=interp(sine,p);bright=a+((b-a)*w+32768>>16)
            ss+=((s*env[v]>>16)*vel[v]>>7)
            bs+=((bright*env[v]>>16)*vel[v]>>7)
        pack=lambda vals,bits:sum(int(x)<<(i*bits) for i,x in enumerate(vals))
        # case is encoded as a positive hex word for portable $fscanf.
        rows.append(f'{pack(incs,32):032x} {ratio:x} {pack(env,16):016x} {pack(vel,8):08x} {retrig:x} {case&0xffffffff:x} {ss} {bs}\n')
    for i in range(64 if smoke else 1024):
        if i<40:
            incs=[(1<<(26+(i//8)%5))+((i%8)-4)*1024 for _ in range(4)]
        else:incs=[randoms.randrange(1,1300000000) for _ in range(4)]
        emit(incs,randoms.choice([58386,65536,73562]),[randoms.randrange(65536) for _ in range(4)],
             [randoms.randrange(128) for _ in range(4)],randoms.randrange(16))
    if not smoke:
        for note in range(1,128):
            for ratio in [58386,65536,73562]:
                inc=round(440*2**((note-69)/12)*2**32/48000)
                emit([inc]*4,ratio,[65535,32768,256,1],[127,100,64,1],0)
        for case,note in enumerate([60,84,96,108,127]):
            size=8192;binno=round(440*2**((note-69)/12)*size/48000);inc=binno*(2**32//size)
            emit([inc]*4,65536,[65535,0,0,0],[127,0,0,0],15)
            legacy=[]
            for j in range(size):
                emit([inc]*4,65536,[65535,0,0,0],[127,0,0,0],0,case)
                legacy.append((interp(banks[0],phases[0])*65535>>16)*127>>7)
            lo,w=config(inc);max_h=[16,8,4,2,1][lo]
            spec.append(dict(case_id=case,note=note,bin=binno,frequency=binno*48000/size,max_harmonic=max_h,legacy=legacy))
    path.parent.mkdir(parents=True,exist_ok=True);path.write_text(''.join(rows),encoding='ascii')
    return spec

def main():
    sys.stdout.reconfigure(encoding='utf-8',errors='replace')
    p=argparse.ArgumentParser();p.add_argument('--out',type=Path,default=ROOT/'docs/evidence/FPGA-高音带限-20261017-v0.1');p.add_argument('--smoke',action='store_true');p.add_argument('--generate-smoke',action='store_true');args=p.parse_args()
    if args.generate_smoke:
        vectors(SRC/'sim/vectors/bandlimit_smoke.txt',True);return
    out=args.out;out.mkdir(parents=True,exist_ok=True);work=ROOT/'tmp/bandlimit-20261017';work.mkdir(parents=True,exist_ok=True)
    spec=vectors(work/'vectors.txt',args.smoke);results=[]
    for name in ['tb_bright_banks','tb_bandlimit_engine']:
        exe=work/(name+'.vvp');capture=work/'audio.csv'
        cmd=[r'C:\iverilog\bin\iverilog.exe','-g2012','-DSIMULATION','-I',str(SRC),'-s',name,'-o',str(exe),str(SRC/'sim'/(name+'.v'))]+list(map(str,(SRC/'rtl/audio').glob('*.v')))+[str(SRC/'sim/gowin_prom_model.v')]
        cp=subprocess.run(cmd,cwd=SRC,capture_output=True);(out/(name+'-compile.log')).write_bytes(cp.stdout+cp.stderr)
        if cp.returncode:raise RuntimeError(cp.stderr.decode(errors='replace'))
        cp=subprocess.run([r'C:\iverilog\bin\vvp.exe',str(exe),'+VECTORS='+str(work/'vectors.txt'),'+CAPTURE='+str(capture)],cwd=SRC,capture_output=True,timeout=300)
        (out/(name+'.log')).write_bytes(cp.stdout+cp.stderr);print(cp.stdout.decode(errors='replace'),flush=True)
        results.append(dict(test=name,exit=cp.returncode));(out/'results.json').write_text(json.dumps(results,indent=2))
        if cp.returncode:raise RuntimeError(name+' failed')
        if capture.exists():(out/'audio.csv').write_bytes(capture.read_bytes())
    if spec:
        data=list(csv.DictReader((out/'audio.csv').open()));metrics=[]
        for s in spec:
            actual=np.array([int(r['bright']) for r in data if int(r['case_id'])==s['case_id']]);legacy=np.array(s.pop('legacy'));assert len(actual)==8192
            allowed=[h*s['bin'] for h in range(1,s['max_harmonic']+1) if h*s['bin']<4096]
            def residual(x):
                power=abs(np.fft.rfft(x))**2;mask=np.ones(len(power),dtype=bool);mask[0]=False;mask[allowed]=False
                return float(power[mask].sum()/power[s['bin']])
            old=residual(legacy);new=residual(actual)
            s.update(alias_before_dbc=float(10*np.log10(old)),alias_after_dbc=float(10*np.log10(new)),reduction_db=float(10*np.log10(old/new)))
            if s['note']>=96:assert s['reduction_db']>35
            if s['note']==60:assert np.array_equal(actual,legacy)
            metrics.append(s)
        (out/'spectrum.json').write_text(json.dumps(metrics,indent=2));print(json.dumps(metrics,indent=2))

if __name__=='__main__':main()
