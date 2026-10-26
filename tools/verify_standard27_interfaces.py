"""Verify implementation route envelopes, receipt policies and delayed IO models."""
import argparse,pathlib,subprocess,json,hashlib,re,os,shutil
from bs4 import BeautifulSoup
repo=pathlib.Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--source-root',type=pathlib.Path,required=True)
p.add_argument('--output-dir',type=pathlib.Path,required=True);a=p.parse_args()
src=a.source_root.resolve();out=a.output_dir.resolve();out.mkdir(parents=True,exist_ok=True)
ports=['i2s_bck','i2s_lrck','i2s_din','adc_cs_n','adc_sck','adc_mosi']
summaries=[]
for suffix,policy in [('', 'IdleOnly'),('.strict','Strict')]:
 receipt=json.loads((src/f'build/receipts/standard27{suffix}.json').read_text(encoding='utf-8-sig'))
 assert receipt['TimeoutPolicy']==policy
 assert hashlib.sha256(pathlib.Path(receipt['Bitstream']).read_bytes()).hexdigest()==receipt['BitstreamSha256']
 assert hashlib.sha256(pathlib.Path(receipt['GeneratedWrapper']).read_bytes()).hexdigest()==receipt['GeneratedWrapperSha256']
 for entry in receipt['Inputs']:
  assert hashlib.sha256(pathlib.Path(entry['Path']).read_bytes()).hexdigest()==entry['Sha256'],entry['Path']
 pn=pathlib.Path(receipt['Bitstream']).parent
 soup=BeautifulSoup((pn/'instrument_tr_content.html').read_text(errors='replace'),'html.parser')
 tables=soup.find_all('table');sta={}
 for tr in tables[1].find_all('tr'):
  cells=[x.get_text(' ',strip=True) for x in tr.find_all(['td','th'])]
  if len(cells)==2:sta[cells[0]]=cells[1]
 assert int(sta['Numbers of Setup Violated Endpoints'])==0 and int(sta['Numbers of Hold Violated Endpoints'])==0
 sdc=(src/'constraints/primer20k_i2s_27m.sdc').read_text(encoding='utf-8')
 assert 'set_max_delay 20 -to [get_ports {'+' '.join(ports)+'}]' in sdc
 assert 'set_max_delay 20 -from [get_ports {adc_miso}]' in sdc
 assert 'set_min_delay 0 -from [get_ports {adc_miso}]' not in sdc
 assert 'set_false_path ' not in sdc and 'set_multicycle_path ' not in sdc
 report=(pn/'instrument.rpt.txt').read_text(errors='replace')
 for port in ports+['adc_miso']:
  assert re.search(r'^'+port+r'\s+\|.*\|\s*Y\s*\|',report,re.M),port
 # Confirm the solver emitted analyzed path sections for both 20ns max-delay constraints.
 constrained=[]
 for h4 in soup.find_all('h4'):
  title=h4.get_text(' ',strip=True)
  if 'Timing Path Constraint' not in title or 'set_max_delay 20' not in title:continue
  table=h4.find_next('table')
  assert table is not None,title
  values={}
  for tr in table.find_all('tr'):
   cells=[x.get_text(' ',strip=True) for x in tr.find_all(['td','th'])]
   if len(cells)==2:values[cells[0]]=cells[1]
  constrained.append({'constraint':title,'first_path':values})
 output_constraint='set_max_delay 20 -to [get_ports {'+' '.join(ports)+'}]'
 miso_constraint='set_max_delay 20 -from [get_ports {adc_miso}]'
 assert any(output_constraint in x['constraint'] and float(x['first_path']['Slack'])>0 for x in constrained)
 assert any(miso_constraint in x['constraint'] and float(x['first_path']['Slack'])>0 for x in constrained)
 summaries.append({'policy':policy,'bitstream_sha256':receipt['BitstreamSha256'],
   'sta':sta,'constrained_path_samples':constrained,
   'constrained_ports':ports+['adc_miso'],'coverage_basis':'exact SDC port sets + implementation IO table + solver path samples; report lists worst paths only'})
 (out/f'{policy}.timing.html').write_text(str(soup),encoding='utf-8')
 budgets={'i2s_setup':5*1000/27-20-20-10-20,'i2s_hold':4*1000/27-20-20-10-20,
  'adc_mosi':2000-20-20-10-50,'adc_cs_setup':2000-20-20-10-100,
  'adc_miso_setup':2000-20-20-800-20-10,'adc_pulse':2000-20-10-500,'adc_cs_gap':1000-20-10-500}
 assert min(budgets.values())>0
summary={'implementations':summaries,'remaining_budgets_ns':budgets,
 'assumptions':{'fpga_route_max_ns':20,'board_one_way_max_ns':10,'adc_delay_budget_ns':800,'pcm_setup_hold_budget_ns':20}}
(out/'implementation.json').write_text(json.dumps(summary,indent=2),encoding='utf-8')
# Apply worst-case route/board/device delays to the existing pin-level models.
vvp=out/'io_budget.vvp'
args=[r'C:\iverilog\bin\iverilog.exe','-g2012','-DSIMULATION','-s','tb_standard27_io_budget','-I','.', '-o',str(vvp),str(repo/'tools/verification/tb_standard27_io_budget.v'),'rtl/audio/i2s_tx.v','rtl/audio/mcp3208_spi.v','sim/mcp3208_model.v']
c=subprocess.run(args,cwd=src,capture_output=True,timeout=30);(out/'io.compile.log').write_bytes(c.stdout+c.stderr);assert c.returncode==0
r=subprocess.run([r'C:\iverilog\bin\vvp.exe','-N',str(vvp)],cwd=src,capture_output=True,timeout=30)
(out/'io.run.log').write_bytes(r.stdout+r.stderr);assert r.returncode==0 and b'PASS' in r.stdout,r.stdout
# Policy mismatch and generated-wrapper tamper must stop before programming.
fixture=out/'program-fixture';(fixture/'build/receipts').mkdir(parents=True,exist_ok=True);(fixture/'sim').mkdir(exist_ok=True)
for name in ['program_sram.ps1','profile_helpers.ps1','profiles.tsv']:shutil.copy2(src/'build'/name,fixture/'build'/name)
(fixture/'sim/run_simulation.ps1').write_text('param([string]$Suite)\nexit 0\n',encoding='utf-8-sig')
env=os.environ.copy()
for key in list(env):
 if key.lower()=='psmodulepath':del env[key]
tests=[]
for name,receipt,phrase in [('mismatch',{'TimeoutPolicy':'IdleOnly'},'Timeout policy differs'),
 ('wrapper_tamper',{'TimeoutPolicy':'Strict','GeneratedWrapper':str(fixture/'wrapper.v'),'GeneratedWrapperSha256':'0'*64},'Generated wrapper changed')]:
 (fixture/'wrapper.v').write_text('tampered',encoding='ascii')
 (fixture/'build/receipts/standard27.strict.json').write_text(json.dumps(receipt),encoding='utf-8')
 cmd=['powershell.exe','-NoProfile','-ExecutionPolicy','Bypass','-File',str(fixture/'build/program_sram.ps1'),'-Profile','standard27','-HostTimeoutPolicy','Strict','-Programmer',str(fixture/'never-run.exe')]
 result=subprocess.run(cmd,capture_output=True,timeout=20,env=env)
 log=result.stdout+result.stderr;(out/(name+'.log')).write_bytes(log)
 assert result.returncode!=0 and phrase.encode() in log
 tests.append({'case':name,'exit':result.returncode,'blocked':True})
(out/'checks.json').write_text(json.dumps({'io_compile_exit':c.returncode,'io_run_exit':r.returncode,'program_guards':tests,'passed':True},indent=2),encoding='utf-8')
print(json.dumps({'passed':True,'policies':len(summaries),'remaining_budgets_ns':budgets,'program_guards':tests},indent=2))
