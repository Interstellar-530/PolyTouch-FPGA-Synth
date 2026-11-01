"""Exercise gate selection, failures and programmer interception without hardware."""
import pathlib, shutil, subprocess, json, os
repo=pathlib.Path(__file__).resolve().parents[1]
work=repo/'tmp/reorganization-20261101/gate-policy'
base=repo/'source'
fixture=work/'fixture/source'
evidence=work/'evidence'; evidence.mkdir(parents=True,exist_ok=True)
for name in ['sim/run_simulation.ps1','sim/gate_process.ps1','rtl/audio/pt8211_tx.v','build/program_sram.ps1','build/profile_helpers.ps1']:
 p=fixture/name;p.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(base/name,p)
results=[]
def call(name,args,expected,contains=None):
 env=os.environ.copy()
 for key in list(env):
  if key.lower()=='psmodulepath': del env[key]
 p=subprocess.run(['powershell.exe','-NoProfile','-ExecutionPolicy','Bypass','-File']+list(map(str,args)),cwd=repo,capture_output=True,timeout=30,env=env)
 out=(p.stdout+p.stderr).decode('utf-8',errors='replace')
 (evidence/(name+'.log')).write_text(out,encoding='utf-8')
 ok=(p.returncode==0 if expected==0 else p.returncode!=0) and (contains is None or contains in out)
 results.append(dict(name=name,exit=p.returncode,passed=ok));print(results[-1],flush=True)
 return out
gate=base/'sim/run_simulation.ps1'
quick=call('quick_list',[gate,'-ListTests'],0,'tb_top_host_ctrl')
full=call('full_list',[gate,'-Suite','Full','-ListTests'],0,'tb_audio_capture')
assert 'tb_audio_capture' not in quick and 'tb_ram_audio_datapath_64' not in quick
assert 'tb_ram_audio_datapath_64' in full
call('unknown_test',[gate,'-Tests','not_a_real_test','-ListTests'],1,'Unknown test')
call('empty_selection',[gate,'-Tests','tb_audio_capture','-SkipAudioCapture','-ListTests'],1,'No tests selected')
fg=fixture/'sim/run_simulation.ps1';tb=fixture/'sim/tb_tick_rate.v'
common=['-Tests','tb_tick_rate','-BuildDir',work/'build','-AudioCaptureDir',work/'capture','-MetricsDir',work/'metrics']
if tb.exists():
 print('Reset owned fixture:',str(tb),flush=True)
 tb.unlink()
call('missing_bench',[fg]+common,1)
tb.write_text('module tb_tick_rate; initial begin $fatal(1,"POLICY_SENTINEL"); end endmodule',encoding='ascii')
call('fatal_rejected',[fg]+common,1)
summary=json.loads((work/'metrics/gate-result.json').read_text(encoding='utf-8-sig'))
assert summary['Results'][0]['RunExit']==1 and not summary['Passed']
tb.write_text('module tb_tick_rate; syntax is broken; endmodule',encoding='ascii')
call('compile_rejected',[fg]+common,1)
summary=json.loads((work/'metrics/gate-result.json').read_text(encoding='utf-8-sig'))
assert summary['Results'][0]['CompileExit']!=0 and summary['Results'][0]['RunExit'] is None
tb.write_text('module tb_tick_rate; reg c=0; always #1 c=~c; endmodule',encoding='ascii')
call('timeout_rejected',[fg]+common+['-TimeoutSeconds','1'],1)
summary=json.loads((work/'metrics/gate-result.json').read_text(encoding='utf-8-sig'))
assert summary['Results'][0]['RunExit']==124
# Programmer uses a gate stub which always fails; it must stop before tool lookup.
fg.write_text('param([string]$Suite)\nWrite-Output "GATE_SUITE=$Suite"\nexit 1\n',encoding='utf-8-sig')
for suite in ['Quick','Full']:
 out=call('program_reject_'+suite,[fixture/'build/program_sram.ps1','-SimulationSuite',suite,'-Programmer',work/'must-not-run.exe'],1,'GATE_SUITE='+suite)
 assert 'No successful' not in out, 'Programmer continued to receipt lookup after failed gate'
(evidence/'results.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
raise SystemExit(0 if all(r['passed'] for r in results) else 1)
