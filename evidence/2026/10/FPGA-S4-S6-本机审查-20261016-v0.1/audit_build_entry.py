"""Elaborate only the source manifest of the default build entry.

This reproduces the missing-module defect without running Gowin or the gate.
"""
from pathlib import Path
import argparse,json,re,subprocess,sys


def main():
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True)
    a=p.parse_args();src=a.source.resolve();out=Path(__file__).resolve().parent
    script=(src/'build/build_instrument.tcl').read_text(encoding='utf-8').split('} else {')[0]
    files=[]
    for raw in re.findall(r'add_file\s+(.+)',script):
        m=re.search(r'\[file join \$root ([^\]]+)\]',raw)
        path=src.joinpath(*m.group(1).split()) if m else src/'rtl/audio'/(
          'gpio_keyboard.v' if '$gpio_file' in raw else 'i2s_tx.v')
        if path.suffix=='.v':files.append(path)
    workspace=next(x for x in out.parents if (x/'AGENTS.md').is_file())
    exe=workspace/'tmp/s4s6-review-20261016/sim-build/default-entry.vvp'
    exe.parent.mkdir(parents=True,exist_ok=True)
    command=[r'C:\iverilog\bin\iverilog.exe','-g2012','-I',str(src),'-s','top','-o',str(exe)]+list(map(str,files))
    run=subprocess.run(command,cwd=src,capture_output=True)
    text=(run.stdout+run.stderr).decode('utf-8','replace')
    (out/'default-build-entry.log').write_text(text,encoding='utf-8')
    missing=re.findall(r'Unknown module type: (\w+)',text)
    result=dict(script='build/build.ps1 -> build_instrument.tcl',source_files=len(files),
      elaboration_exit=run.returncode,missing_modules=sorted(set(missing)),command=command)
    (out/'default-build-entry.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k!='command'},indent=2))
    if run.returncode==0 or not missing:raise SystemExit('Expected missing module finding did not reproduce')


if __name__=='__main__':main()
