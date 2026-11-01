"""Verify policy parameters on the real build roots, without hardware."""
import pathlib,subprocess,json,os,argparse
repo=pathlib.Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument('--source-root',type=pathlib.Path,default=repo/'source')
src=parser.parse_args().source_root.resolve()
work=repo/'tmp/candidate-fix-20261023/policy';work.mkdir(parents=True,exist_ok=True)
observer=work/'observer.v'
observer.write_text('''module policy_observer;
initial begin #1;
 if (`ROOT.u_top.HOST_KBD_TIMEOUT_POLICY != `EXPECTED_POLICY) $fatal(1,"top policy mismatch");
 if (`ROOT.u_top.g_host_kbd.u_host_kbd.TIMEOUT_POLICY != `EXPECTED_POLICY) $fatal(1,"host policy mismatch");
 $display("PASS policy=%0d",`EXPECTED_POLICY); $finish;
end
endmodule
''',encoding='ascii')
results=[]
def check(root,policy,wrapper=None):
 name=root+'-'+str(policy);out=work/(name+'.vvp')
 wrapper=wrapper or src/'build/isolated'/f'{root}.v'
 args=[r'C:\iverilog\bin\iverilog.exe','-g2012','-DSIMULATION',f'-DROOT={root}',f'-DEXPECTED_POLICY={policy}','-s',root,'-s','policy_observer','-I','.', '-o',str(out),str(wrapper),str(observer),'rtl/top.v','sim/gowin_prom_model.v']
 if wrapper.parent==src/'build/isolated':args.insert(1,f'-P{root}.HOST_KBD_TIMEOUT_POLICY={policy}')
 args.extend(str(p) for p in (src/'rtl/audio').glob('*.v'))
 c=subprocess.run(args,cwd=src,capture_output=True,timeout=60)
 (work/(name+'.compile.log')).write_bytes(c.stdout+c.stderr)
 assert c.returncode==0,(name,c.returncode)
 r=subprocess.run([r'C:\iverilog\bin\vvp.exe','-N',str(out)],cwd=src,capture_output=True,timeout=30)
 (work/(name+'.run.log')).write_bytes(r.stdout+r.stderr)
 assert r.returncode==0 and b'PASS' in r.stdout,(name,r.returncode,r.stdout)
 results.append({'root':root,'policy':policy,'compile':c.returncode,'run':r.returncode,'wrapper':str(wrapper)})
for root in ['top_std27_build','top_dbg8usb_build']:
 for policy in [0,1]:check(root,policy)
# Verify generated Gowin inputs directly, without applying an Icarus override.
for filename,policy in [('standard27.json',1),('standard27.strict.json',0)]:
 receipt=src/'build/receipts'/filename
 if receipt.exists():
  data=json.loads(receipt.read_text(encoding='utf-8-sig'))
  check('top_std27_build',policy,pathlib.Path(data['GeneratedWrapper']))
(work/'results.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
print(json.dumps(results,indent=2))
