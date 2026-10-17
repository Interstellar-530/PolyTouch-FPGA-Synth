"""Vendor PLL and64-oscillator two-clock I2S checks; no programming."""
from pathlib import Path
import argparse,json,subprocess,sys

def main():
 sys.stdout.reconfigure(encoding='utf-8',errors='replace')
 root=Path(__file__).resolve().parents[1];src=root/'output/handoff_milestone2_20261008/source'
 p=argparse.ArgumentParser();p.add_argument('--out',type=Path,default=root/'docs/evidence/FPGA-PLL时钟-20261017-v0.1/vendor');p.add_argument('--clock-only',action='store_true');args=p.parse_args()
 out=args.out;out.mkdir(parents=True,exist_ok=True);work=root/'tmp/pll-20261017';work.mkdir(parents=True,exist_ok=True);results=[]
 for name in (['tb_audio_pll_clock'] if args.clock_only else ['tb_audio_pll_clock','tb_ram_audio_pll_probe']):
  exe=work/(name+'.vvp')
  cmd=[r'C:\iverilog\bin\iverilog.exe','-g2012','-I',str(src),'-s',name,'-o',str(exe),str(src/'sim'/(name+'.v'))]
  cmd+=list(map(str,(src/'rtl/audio').glob('*.v')))+[str(src/'rtl/prototypes/ram_audio_pll_probe.v'),str(src/'sim/i2s_rx_model.v'),r'E:\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\simlib\gw2a\prim_sim.v']
  cp=subprocess.run(cmd,cwd=src,capture_output=True);(out/(name+'-compile.log')).write_bytes(cp.stdout+cp.stderr)
  if cp.returncode:raise RuntimeError(cp.stderr.decode(errors='replace')[-3000:])
  cp=subprocess.run([r'C:\iverilog\bin\vvp.exe',str(exe)],cwd=src,capture_output=True,timeout=300)
  (out/(name+'.log')).write_bytes(cp.stdout+cp.stderr);print(cp.stdout.decode(errors='replace'),flush=True)
  results.append(dict(test=name,exit=cp.returncode,model='installed Gowin GW2A primitives'));(out/'results.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
  if cp.returncode:raise RuntimeError(name+' failed')

if __name__=='__main__':main()
