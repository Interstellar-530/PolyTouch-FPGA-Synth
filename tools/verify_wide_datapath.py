"""Check portable arithmetic and the installed Gowin primitive model."""
from pathlib import Path
import argparse,json,subprocess,sys

def main():
 sys.stdout.reconfigure(encoding='utf-8',errors='replace')
 root=Path(__file__).resolve().parents[1];src=root/'output/handoff_milestone2_20261008/source'
 p=argparse.ArgumentParser();p.add_argument('--out',type=Path,default=root/'docs/evidence/FPGA-宽乘法通路-20261017-v0.1/model');args=p.parse_args()
 out=args.out;out.mkdir(parents=True,exist_ok=True);work=root/'tmp/wide-datapath-20261017';work.mkdir(parents=True,exist_ok=True);results=[]
 for name in ['portable','vendor']:
  exe=work/(name+'.vvp')
  cmd=[r'C:\iverilog\bin\iverilog.exe','-g2012','-s','tb_split_audio_multiplier','-o',str(exe)]
  cmd+=['-DSIMULATION'] if name=='portable' else ['-DGOWIN_VENDOR_MODEL']
  cmd+=list(map(str,[src/'rtl/audio/split_audio_multiplier.v',src/'sim/tb_split_audio_multiplier.v']))
  if name=='vendor':cmd+=[r'E:\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\simlib\gw2a\prim_sim.v']
  cp=subprocess.run(cmd,cwd=src,capture_output=True);(out/(name+'-compile.log')).write_bytes(cp.stdout+cp.stderr)
  if cp.returncode:raise RuntimeError(cp.stderr.decode(errors='replace')[-2000:])
  cp=subprocess.run([r'C:\iverilog\bin\vvp.exe',str(exe)],cwd=src,capture_output=True,timeout=120)
  (out/(name+'.log')).write_bytes(cp.stdout+cp.stderr);print(cp.stdout.decode(errors='replace'),flush=True)
  results.append(dict(model=name,exit=cp.returncode));(out/'results.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
  if cp.returncode:raise RuntimeError(name+' failed')

if __name__=='__main__':main()
