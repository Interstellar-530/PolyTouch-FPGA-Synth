"""Isolated synthesis of the future wide arithmetic backend; no board changes."""
from pathlib import Path
import argparse,json,subprocess,sys,time
from measure_timbre_resources import resource_metrics
from measure_architecture import timing_summary

def main():
 sys.stdout.reconfigure(encoding='utf-8',errors='replace')
 root=Path(__file__).resolve().parents[1];src=root/'source'
 p=argparse.ArgumentParser();p.add_argument('--out',type=Path,default=root/'evidence/2026/10/FPGA-宽乘法通路-20261017-v0.1/resources');p.add_argument('--state',action='store_true');args=p.parse_args()
 out=args.out;out.mkdir(parents=True,exist_ok=True);work=root/'tmp/wide-datapath-20261017';work.mkdir(parents=True,exist_ok=True);results=[]
 for width in ([32] if args.state else [24,33]):
  name=f'width{width}';project=work/name/str(time.time_ns());project.mkdir(parents=True)
  wrapper=project/'wide_top.v'
  wrapper.write_text(f'module wide_top(input wire clk,rst,enable,input wire signed[{width-1}:0]a,input wire signed[17:0]b,output reg signed[{width+17}:0]p);\nreg signed[{width-1}:0] aq;reg signed[17:0]bq;wire signed[{width+17}:0]result;\nalways @(posedge clk)if(rst)begin aq<=0;bq<=0;p<=0;end else if(enable)begin aq<=a;bq<=b;p<=result;end\nsplit_audio_multiplier #(.A_WIDTH({width})) u_mult(clk,rst,enable,aq,bq,result);\nendmodule\n',encoding='ascii')
  module='voice_state_ram' if args.state else 'split_audio_multiplier'
  if args.state:
   wrapper.write_text('module wide_top(input wire clk,rst,we,re,input wire[8:0]wa,ra,input wire[31:0]wd,output wire[31:0]rd,output wire valid,ready);\nvoice_state_ram u_state(clk,rst,we,wa,wd,re,ra,rd,valid,ready);\nendmodule\n',encoding='ascii')
  tcl=project/'run.tcl'
  tcl.write_text('create_project -name wide -dir {%s} -pn GW2A-LV18PG256C8/I7 -device_version C\nadd_file {%s}\nadd_file {%s}\nset_option -top_module wide_top\nset_option -output_base_name wide\ncd {%s}\nrun syn\n'%(project.as_posix(),wrapper.as_posix(),(src/'rtl/audio'/(module+'.v')).as_posix(),project.as_posix()),encoding='utf-8')
  cp=subprocess.run([r'E:\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\bin\gw_sh.exe',str(tcl)],cwd=project,capture_output=True,timeout=180)
  (out/(name+'.log')).write_bytes(cp.stdout+cp.stderr)
  reports=list(project.rglob('*syn.rpt.html'))
  if cp.returncode or not reports:raise RuntimeError((cp.stdout+cp.stderr).decode(errors='replace')[-2000:])
  report=reports[0];(out/(name+'-syn.rpt.html')).write_bytes(report.read_bytes())
  metric=resource_metrics(name,report)
  if args.state:assert metric['bsram']==1 and metric['dsp_macro_equivalent']==0
  else:assert metric['dsp_macro_equivalent']==1
  metric['scope']='isolated state RAM; not production integration' if args.state else 'isolated backend with external input/output registers; not production integration'
  metric['timing']=timing_summary(report);results.append(metric)
  print(json.dumps(metric),flush=True);(out/'metrics.json').write_text(json.dumps(results,indent=2),encoding='utf-8')

if __name__=='__main__':main()
