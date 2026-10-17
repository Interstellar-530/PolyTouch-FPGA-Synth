"""Same-profile synthesis comparison of preserved and optimized architecture."""
from pathlib import Path
import argparse,json,subprocess,sys,time,re,html
from measure_timbre_resources import resource_metrics

def timing_summary(report):
    lines=[s.strip() for s in html.unescape(re.sub('<[^>]+>','\n',report.read_text(encoding='utf-8',errors='replace'))).splitlines() if s.strip()]
    start=lines.index('Path Summary:');part=lines[start:]
    following=lambda key:part[part.index(key)+1]
    return dict(scope='pre-route synthesis estimate; default 10 ns constraint; not routed timing',
                slack_ns=float(following('Slack')),arrival_ns=float(following('Data Arrival Time')),
                required_ns=float(following('Data Required Time')),start=following('From'),end=following('To'),
                logic_levels=int(following('Logic Level:')))

def main():
    sys.stdout.reconfigure(encoding='utf-8',errors='replace')
    root=Path(__file__).resolve().parents[1];source=root/'output/handoff_milestone2_20261008/source'
    parser=argparse.ArgumentParser();parser.add_argument('--out',type=Path);parser.add_argument('--baseline-ref');parser.add_argument('--analyze-only',action='store_true');args=parser.parse_args()
    work=root/'tmp/architecture-resource-20261016';work.mkdir(parents=True,exist_ok=True)
    out=args.out or root/'docs/evidence/FPGA-架构优化-20261016-v0.1/resources';out.mkdir(parents=True,exist_ok=True)
    if args.analyze_only:
        timings={name:timing_summary(out/(name+'-syn.rpt.html')) for name in ['baseline','optimized']}
        (out/'timing-summary.json').write_text(json.dumps(timings,indent=2),encoding='utf-8');print(json.dumps(timings,indent=2));return
    overrides={}
    for name in ['top','global_crossfade','shared_wavetable_engine','pressure_bend']:
        if args.baseline_ref:
            relative='rtl/top.v' if name=='top' else 'rtl/audio/'+name+'.v'
            text=subprocess.check_output(['git','show',args.baseline_ref+':'+source.relative_to(root).as_posix()+'/'+relative],cwd=root).decode('utf-8')
        else:
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
    timings={name:timing_summary(out/(name+'-syn.rpt.html')) for name in ['baseline','optimized']}
    (out/'timing-summary.json').write_text(json.dumps(timings,indent=2),encoding='utf-8');print(json.dumps(timings,indent=2))

if __name__=='__main__':main()
