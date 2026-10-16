"""Same-profile synthesis comparison of preserved and optimized architecture."""
from pathlib import Path
import json,subprocess,sys,time
from measure_timbre_resources import resource_metrics

def main():
    sys.stdout.reconfigure(encoding='utf-8',errors='replace')
    root=Path(__file__).resolve().parents[1];source=root/'output/handoff_milestone2_20261008/source'
    work=root/'tmp/architecture-resource-20261016';work.mkdir(parents=True,exist_ok=True)
    out=root/'docs/evidence/FPGA-架构优化-20261016-v0.1/resources';out.mkdir(parents=True,exist_ok=True)
    overrides={}
    for name in ['top','global_crossfade','shared_wavetable_engine','pressure_bend']:
        text=(source/'sim/reference'/('baseline_'+name+'.v')).read_text(encoding='utf-8')
        path=work/(name+'.v')
        path.write_text(text.replace('module baseline_'+name,'module '+name,1),encoding='utf-8')
        overrides[name+'.v']=path
    metrics=[]
    for name in ['baseline','optimized']:
        project=work/name/str(time.time_ns());harness=work/(name+'.tcl')
        override=''
        if name=='baseline':
            cases='\n'.join('if {[file tail $path] eq "%s"} {set path {%s}}'%(leaf,path.as_posix()) for leaf,path in overrides.items())
            override='rename add_file original_add_file\nproc add_file {path} {\n'+cases+'\noriginal_add_file $path\n}\n'
        harness.write_text('rename run original_run\nproc run {args} {original_run syn}\nset ::env(FPGA_BUILD_RUN_DIR) {%s}\n%s\nsource {%s}\n'%(
            project.as_posix(),override,(source/'build/build_top_i2s_std.tcl').as_posix()),encoding='utf-8')
        cp=subprocess.run([r'E:\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\bin\gw_sh.exe',str(harness)],cwd=source,capture_output=True,timeout=180)
        (out/(name+'.log')).write_bytes(cp.stdout+cp.stderr)
        reports=list(project.rglob('*syn.rpt.html'))
        if cp.returncode or not reports:raise RuntimeError((cp.stdout+cp.stderr).decode('utf-8','replace')[-2500:])
        report=reports[0];(out/(name+'-syn.rpt.html')).write_bytes(report.read_bytes())
        for path in report.parent.glob('*_syn_resource.html'):(out/(name+'-hierarchy.html')).write_bytes(path.read_bytes())
        metrics.append(resource_metrics(name,report))
        (out/'resource-metrics.json').write_text(json.dumps(metrics,indent=2),encoding='utf-8')
        print(json.dumps(metrics[-1]),flush=True)

if __name__=='__main__':main()
