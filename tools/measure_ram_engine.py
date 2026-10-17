"""Synthesize8/32/dual32 RAM oscillator prototypes with real Gowin primitives."""
from pathlib import Path
import argparse,json,subprocess,time,sys,shutil
from measure_timbre_resources import resource_metrics
from measure_architecture import timing_summary

def main():
 sys.stdout.reconfigure(encoding='utf-8',errors='replace')
 root=Path(__file__).resolve().parents[1];src=root/'output/handoff_milestone2_20261008/source'
 p=argparse.ArgumentParser();p.add_argument('--out',type=Path,default=root/'docs/evidence/FPGA-RAM波表核心-20261017-v0.1/resources');p.add_argument('--audio',action='store_true');args=p.parse_args()
 out=args.out;out.mkdir(parents=True,exist_ok=True);work=root/'tmp/ram-engine-resource-20261017';work.mkdir(parents=True,exist_ok=True);results=[]
 for total in [8,32,64]:
  lanes=2 if total==64 else 1;count=total//lanes;period=256 if count==8 else 1024;name=f'voices{total}'
  project=work/name/str(time.time_ns());project.mkdir(parents=True);wrapper=project/'ram_top.v'
  wrapper.write_text(f'''module ram_top(input wire clk,rst,tick,cv,cl,input wire[4:0]id,input wire[31:0]inc,input wire[15:0]env,input wire[6:0]vel,input wire rt,
 output wire cr,busy,initialized,valid,output wire signed[31:0]sine,bright);
 wire[{lanes-1}:0]ready,busy_v,init_v,valid_v;wire signed[31:0]ss[0:{lanes-1}],bs[0:{lanes-1}];
 genvar g;generate for(g=0;g<{lanes};g=g+1)begin:lane
 ram_wavetable_engine #(.VOICE_COUNT({count}),.FRAME_CYCLES({period})) u_core(clk,rst,tick,cv && ({lanes}==1 || cl==g),ready[g],id,inc,env,vel,rt,ss[g],bs[g],valid_v[g],busy_v[g],init_v[g],1'b0,,33'sd0,18'sd0,);
 end endgenerate
 assign cr=ready[{0 if lanes==1 else 'cl'}];assign busy=|busy_v;assign initialized=&init_v;assign valid=&valid_v;
 assign sine={'ss[0]' if lanes==1 else 'ss[0]+ss[1]'};assign bright={'bs[0]' if lanes==1 else 'bs[0]+bs[1]'};
 endmodule
''',encoding='ascii')
  files=['ram_wavetable_engine','voice_state_ram','split_audio_multiplier','gowin_prom_wave_sine','gowin_prom_bright_bank']
  if args.audio:
   wrapper.write_text(f'''module ram_top(input wire clk,rst,cv,input wire[5:0]id,input wire[31:0]inc,input wire[15:0]env,input wire[6:0]vel,input wire rt,
 input wire[7:0]weight,input wire pressure_enable,input wire[11:0]pressure,input wire mute,
 output wire cr,initialized,valid,tick,bck,lrck,din,output wire signed[23:0]sample,output wire[31:0]clips);
 ram_audio_datapath #(.VOICES({total}),.CLK_HZ({period*48000})) u_audio(clk,rst,cv,cr,id,inc,env,vel,rt,weight,pressure_enable,pressure,mute,bck,lrck,din,tick,sample,valid,clips,initialized);
 endmodule
''',encoding='ascii')
   files+=['ram_audio_datapath','ram_audio_compute','wide_master','i2s_tx']
   header_dir=project/'rtl/audio';header_dir.mkdir(parents=True)
   for header in (src/'rtl/audio').glob('*.vh'):shutil.copy2(header,header_dir/header.name)
  tcl=project/'run.tcl';add='\n'.join('add_file {%s}'%(src/'rtl/audio'/(f+'.v')).as_posix() for f in files)
  tcl.write_text('create_project -name ram -dir {%s} -pn GW2A-LV18PG256C8/I7 -device_version C\nadd_file {%s}\n%s\nset_option -top_module ram_top\nset_option -output_base_name ram\ncd {%s}\nrun syn\n'%(project.as_posix(),wrapper.as_posix(),add,project.as_posix()),encoding='utf-8')
  cp=subprocess.run([r'E:\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\bin\gw_sh.exe',str(tcl)],cwd=project,capture_output=True,timeout=180)
  (out/(name+'.log')).write_bytes(cp.stdout+cp.stderr);reports=list(project.rglob('*syn.rpt.html'))
  if cp.returncode or not reports:raise RuntimeError((cp.stdout+cp.stderr).decode(errors='replace')[-3000:])
  report=reports[0];(out/(name+'-syn.rpt.html')).write_bytes(report.read_bytes());metric=resource_metrics(name,report)
  assert metric['bsram']==5*lanes and metric['dsp_macro_equivalent']==lanes
  metric.update(voices=total,lanes=lanes,cycles=27*count+(6 if args.audio else 0),period=period,scope='compute/master/I2S prototype; no event/ADSR/PLL integration' if args.audio else 'oscillator compute prototype; no event/ADSR/I2S/PLL integration',timing=timing_summary(report));results.append(metric)
  (out/'metrics.json').write_text(json.dumps(results,indent=2),encoding='utf-8');print(json.dumps(metric),flush=True)

if __name__=='__main__':main()
