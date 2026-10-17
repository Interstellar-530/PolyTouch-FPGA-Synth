"""Directed shared-wide-master and serial-I2S checks for8/32/64 prototypes."""
from pathlib import Path
import argparse,json,subprocess,sys

def main():
 sys.stdout.reconfigure(encoding='utf-8',errors='replace')
 root=Path(__file__).resolve().parents[1];src=root/'output/handoff_milestone2_20261008/source'
 p=argparse.ArgumentParser();p.add_argument('--out',type=Path,default=root/'docs/evidence/FPGA-宽主混合-20261017-v0.1/audio');p.add_argument('--voices',type=int,choices=[8,32,64]);p.add_argument('--vendor',action='store_true');args=p.parse_args()
 out=args.out;out.mkdir(parents=True,exist_ok=True);work=root/'tmp/ram-audio-20261017';work.mkdir(parents=True,exist_ok=True);results=[]
 for voices in ([args.voices] if args.voices else [8,32,64]):
  label=str(voices)+('-vendor' if args.vendor else '-portable');exe=work/(label+'.vvp')
  cmd=[r'C:\iverilog\bin\iverilog.exe','-g2012','-I',str(src),'-s','tb_ram_audio_datapath','-Ptb_ram_audio_datapath.VOICES='+str(voices),'-o',str(exe)]
  cmd+=['-DGOWIN_VENDOR_MODEL'] if args.vendor else ['-DSIMULATION']
  cmd+=list(map(str,(src/'rtl/audio').glob('*.v')))+[str(src/'sim/tb_ram_audio_datapath.v'),str(src/'sim/i2s_rx_model.v')]
  cmd+=[r'E:\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\simlib\gw2a\prim_sim.v'] if args.vendor else [str(src/'sim/gowin_prom_model.v')]
  cp=subprocess.run(cmd,cwd=src,capture_output=True);(out/(label+'-compile.log')).write_bytes(cp.stdout+cp.stderr)
  if cp.returncode:raise RuntimeError(cp.stderr.decode(errors='replace')[-3000:])
  cp=subprocess.run([r'C:\iverilog\bin\vvp.exe',str(exe)],cwd=src,capture_output=True,timeout=300)
  (out/(label+'.log')).write_bytes(cp.stdout+cp.stderr);print(cp.stdout.decode(errors='replace'),flush=True)
  results.append(dict(voices=voices,model='vendor' if args.vendor else 'portable',exit=cp.returncode));(out/'results.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
  if cp.returncode:raise RuntimeError(label+' failed')

if __name__=='__main__':main()
