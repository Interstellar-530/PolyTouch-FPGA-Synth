"""Isolated pin-constrained PLL/64-tone timing build. Never programs hardware."""
from pathlib import Path
import argparse,json,subprocess,shutil,time,sys,re,html
from measure_timbre_resources import resource_metrics

def main():
 sys.stdout.reconfigure(encoding='utf-8',errors='replace')
 root=Path(__file__).resolve().parents[1];src=root/'output/handoff_milestone2_20261008/source'
 p=argparse.ArgumentParser();p.add_argument('--out',type=Path,default=root/'docs/evidence/FPGA-PLL时钟-20261017-v0.1/pnr');args=p.parse_args()
 out=args.out;out.mkdir(parents=True,exist_ok=True);project=root/'tmp/pll-probe-20261017'/str(time.time_ns());project.mkdir(parents=True)
 header_dir=project/'rtl/audio';header_dir.mkdir(parents=True)
 for header in (src/'rtl/audio').glob('*.vh'):shutil.copy2(header,header_dir/header.name)
 files=list((src/'rtl/audio').glob('*.v'))+[src/'rtl/prototypes/ram_audio_pll_probe.v',src/'constraints/ram_audio_pll_probe.cst',src/'constraints/ram_audio_pll_probe.sdc']
 commands=['create_project -name pllprobe -dir {%s} -pn GW2A-LV18PG256C8/I7 -device_version C'%project.as_posix()]
 commands+=['add_file {%s}'%f.as_posix() for f in files]
 commands+=['set_option -top_module ram_audio_pll_probe','set_option -output_base_name ram_audio_pll_probe','cd {%s}'%project.as_posix(),'run all']
 tcl=project/'run.tcl';tcl.write_text('\n'.join(commands)+'\n',encoding='utf-8')
 cp=subprocess.run([r'E:\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\bin\gw_sh.exe',str(tcl)],cwd=project,capture_output=True,timeout=300)
 (out/'build.log').write_bytes(cp.stdout+cp.stderr);print((cp.stdout+cp.stderr).decode(errors='replace')[-3500:],flush=True)
 reports=[]
 for f in project.rglob('*'):
  if f.is_file() and ('impl' in f.parts) and f.suffix.lower() in ['.html','.htm','.rpt','.txt','.sdc','.log']:
   target=out/'reports'/f.relative_to(project);target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(f,target);reports.append(target.relative_to(out).as_posix())
 report=list(project.rglob('*syn.rpt.html'))
 result=dict(exit=cp.returncode,scope='isolated64-tone timing/self-test wrapper; no event/ADSR front end, no hardware programming',reports=reports)
 if report:result['resources']=resource_metrics('PLL64probe',report[0])
 timing=list(project.rglob('*_tr_content.html'))
 if timing:
  raw=timing[0].read_text(encoding='utf-8',errors='replace')
  rows=[]
  for row in re.findall(r'<tr[^>]*>(.*?)</tr>',raw,re.S|re.I):
   rows.append([html.unescape(re.sub('<[^>]+>',' ',c)).strip() for c in re.findall(r'<t[dh][^>]*>(.*?)</t[dh]>',row,re.S|re.I)])
  result['timing_rows']=rows[:40]
  (out/'timing-tables.json').write_text(json.dumps(rows,indent=2),encoding='utf-8')
 (out/'build-result.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
 print(json.dumps(result,indent=2),flush=True)
 if cp.returncode:raise RuntimeError('PLL probe build failed; inspect build.log')

if __name__=='__main__':main()
