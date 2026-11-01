"""Independent24-bit reference for RAM-backed8/32/64 oscillator lanes."""
from pathlib import Path
import argparse,subprocess,json,random,csv,sys
import numpy as np
from verify_bandlimit import load,config,interp

ROOT=Path(__file__).resolve().parents[1];SRC=ROOT/'source'
def vectors(path,voices,frames=512,spectrum=False):
 rng=random.Random(20261017+voices);phase=[0]*voices;incs=[0]*voices;env=[0]*voices;vel=[0]*voices;rt=[False]*voices
 sine=load('wave_sine.hex');banks=[load(f'wave_bright_h{h}.hex') for h in [16,8,4,2,1]];rows=[]
 def emit(v,inc=0,e=0,w=0,retrigger=0,case=-1):
  if v>=0:incs[v]=inc;env[v]=e;vel[v]=w;rt[v]=bool(retrigger)
  ss=0;bs=0
  for n in range(voices):
   phase[n]=0 if rt[n] else (phase[n]+incs[n])&0xffffffff;rt[n]=False
   a=interp(sine,phase[n],8);lo,weight=config(incs[n]);b0=interp(banks[lo],phase[n],8);b1=interp(banks[min(lo+1,4)],phase[n],8)
   b=b0+((b1-b0)*weight+32768>>16)
   ss+=(((a*env[n]+32768>>16)*vel[n])+64>>7)
   bs+=(((b*env[n]+32768>>16)*vel[n])+64>>7)
  rows.append(f'{v} {inc:x} {e:x} {w:x} {retrigger} {case} {ss} {bs}\n')
 for f in range(frames):
  v=f if f<voices else rng.randrange(voices) if f%3==0 else -1
  emit(v,rng.randrange(1,1300000000),0 if f%5==0 else rng.randrange(65536),0 if f%7==0 else rng.randrange(128),rng.randrange(2))
 if spectrum:
  for v in range(voices):emit(v,(31+11*v)*(2**32//8192),65535,100,1)
  for f in range(8192):emit(-1,case=0)
 path.parent.mkdir(parents=True,exist_ok=True);path.write_text(''.join(rows),encoding='ascii')

def main():
 sys.stdout.reconfigure(encoding='utf-8',errors='replace')
 p=argparse.ArgumentParser();p.add_argument('--out',type=Path,default=ROOT/'evidence/2026/10/FPGA-RAM波表核心-20261017-v0.1');p.add_argument('--voices',type=int,default=8,choices=[8,32,64]);p.add_argument('--smoke',action='store_true');p.add_argument('--vendor',action='store_true');p.add_argument('--spectrum',action='store_true');p.add_argument('--generate-smoke',action='store_true');args=p.parse_args()
 if args.generate_smoke:vectors(SRC/'sim/vectors/ram_engine_smoke.txt',8,64);return
 out=args.out;out.mkdir(parents=True,exist_ok=True);work=ROOT/'tmp/ram-engine-20261017';work.mkdir(parents=True,exist_ok=True)
 label=f'{args.voices}-'+('vendor' if args.vendor else 'portable');vec=work/(label+'.txt');vectors(vec,args.voices,64 if args.smoke else 512,args.spectrum)
 lanes=2 if args.voices==64 else 1;count=args.voices//lanes;period=256 if count==8 else 1024
 exe=work/(label+'.vvp');capture=work/(label+'.csv')
 cmd=[r'C:\iverilog\bin\iverilog.exe','-g2012','-s','tb_ram_wavetable_engine','-I',str(SRC),'-o',str(exe),
      '-Ptb_ram_wavetable_engine.VOICES='+str(count),'-Ptb_ram_wavetable_engine.LANES='+str(lanes),'-Ptb_ram_wavetable_engine.PERIOD='+str(period)]
 cmd+=['-DGOWIN_VENDOR_MODEL'] if args.vendor else ['-DSIMULATION']
 cmd+=list(map(str,(SRC/'rtl/audio').glob('*.v')))+[str(SRC/'sim/tb_ram_wavetable_engine.v')]
 cmd+=[r'E:\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\simlib\gw2a\prim_sim.v'] if args.vendor else [str(SRC/'sim/gowin_prom_model.v')]
 cp=subprocess.run(cmd,cwd=SRC,capture_output=True);(out/(label+'-compile.log')).write_bytes(cp.stdout+cp.stderr)
 if cp.returncode:raise RuntimeError(cp.stderr.decode(errors='replace')[-3000:])
 cp=subprocess.run([r'C:\iverilog\bin\vvp.exe',str(exe),'+VECTORS='+str(vec),'+CAPTURE='+str(capture)],cwd=SRC,capture_output=True,timeout=600)
 (out/(label+'.log')).write_bytes(cp.stdout+cp.stderr);print(cp.stdout.decode(errors='replace'),flush=True)
 (out/(label+'-results.json')).write_text(json.dumps(dict(voices=args.voices,lanes=lanes,period=period,exit=cp.returncode,model='vendor' if args.vendor else 'portable'),indent=2))
 if cp.returncode:raise RuntimeError(label+' failed')
 if capture.exists():(out/(label+'.csv')).write_bytes(capture.read_bytes())
 if args.spectrum:
  rows=list(csv.DictReader(capture.open()));signal=np.array([int(r['sine']) for r in rows],dtype=float)/args.voices
  assert len(signal)==8192
  fft=np.fft.rfft(signal);bins=np.array([31+11*v for v in range(args.voices)]);amps=abs(fft[bins])*2/8192
  expected=abs(np.fft.rfft(np.array(load('wave_sine.hex')))[1])*2/512*256*65535/65536*100/128/args.voices
  errors=20*np.log10(amps/expected);assert max(abs(errors))<0.02
  residual=abs(fft)**2;residual[0]=0;residual[bins]=0
  metrics=dict(oscillators=args.voices,frames=8192,frequency_bins=bins.tolist(),min_amplitude_error_db=float(min(errors)),max_amplitude_error_db=float(max(errors)),residual_to_fundamental_power_db=float(10*np.log10(residual.sum()/np.sum(abs(fft[bins])**2))),scope='RAM oscillator core, sine component normalized by voice count; no production event/ADSR/I2S integration')
  (out/(label+'-spectrum.json')).write_text(json.dumps(metrics,indent=2));print(json.dumps(metrics),flush=True)

if __name__=='__main__':main()
