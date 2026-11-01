"""Compare two-multiply and one-multiply timbre synthesis. No PnR or JTAG."""
from pathlib import Path
import html,json,re,subprocess,sys,time

def resource_metrics(name, report):
    rows=re.findall(r'<tr>\s*<td[^>]*>(.*?)</td>\s*<td[^>]*>(.*?)</td>',report.read_text(encoding='utf-8'),re.S)
    cells={}
    for a,b in rows:
        a=html.unescape(re.sub('<[^>]+>','',a).replace('&nbsp','')).strip()
        b=html.unescape(re.sub('<[^>]+>','',b)).strip()
        cells.setdefault(a,b)
    number=lambda key:int(re.match(r'\d+',cells.get(key,'0')).group())
    row=dict(variant=name,logic=number('Logic'),registers=number('Register'),
             bsram=number('BSRAM'),mult18x18=number('MULT18X18'),multalu36x18=number('MULTALU36X18'),
             multaddalu18x18=number('MULTADDALU18X18'),mult36x36=number('MULT36X36'),alu54d=number('ALU54D'))
    row['dsp_macro_equivalent']=row['multalu36x18']+row['multaddalu18x18']+2*row['mult36x36']+row['alu54d']+row['mult18x18']/2
    return row

def main():
    sys.stdout.reconfigure(encoding='utf-8',errors='replace')
    root=Path(__file__).resolve().parents[1]
    source=root/'source'
    work=root/'tmp/timbre-resource-20261016';work.mkdir(parents=True,exist_ok=True)
    out=root/'evidence/2026/10/FPGA-音色控制-20261016-v0.1/resources';out.mkdir(parents=True,exist_ok=True)
    original=(source/'rtl/audio/global_crossfade.v').read_text(encoding='utf-8-sig')
    a=original.index('    // Exact identity:');b=original.index('    wire signed [27:0] scaled',a)
    naive=original[:a]+'''    wire signed [26:0] ap = $signed(sine_sum) * $signed({19'd0,(8'hff-active_weight)});
    wire signed [26:0] bp = $signed(bright_sum) * $signed({19'd0,active_weight});
    wire signed [26:0] blend = (ap+bp+27'sd127) >>> 8;
'''+original[b:]
    naive_path=work/'two_multiply.v';naive_path.write_text(naive,encoding='utf-8')
    low_start=original.index('    // Recenter the low 18 bits')
    low_end=original.index('    wire signed [27:0] sine_wide',low_start)
    wide=original[:low_start]+'''    wire signed [27:0] delta_product = difference * $signed({1'b0,active_weight});
'''+original[low_end:]
    wide_path=work/'single_wide.v';wide_path.write_text(wide,encoding='utf-8')
    results=[];metrics=[]
    for name in ['optimized','single_wide','two_multiply']:
        project=work/name/str(time.time_ns())
        harness=work/(name+'.tcl')
        override=''
        if name!='optimized':
            variant=naive_path if name=='two_multiply' else wide_path
            override='''rename add_file original_add_file
proc add_file {path} {
    if {[file tail $path] eq "global_crossfade.v"} {set path {%s}}
    original_add_file $path
}
''' % variant.as_posix()
        harness.write_text('''rename run original_run
proc run {args} {original_run syn}
set ::env(FPGA_BUILD_RUN_DIR) {%s}
%s
source {%s}
''' % (project.as_posix(),override,(source/'build/build_top_i2s_std.tcl').as_posix()),encoding='utf-8')
        cp=subprocess.run([r'E:\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\bin\gw_sh.exe',str(harness)],
                          cwd=source,capture_output=True,timeout=180)
        (out/(name+'.log')).write_bytes(cp.stdout+cp.stderr)
        reports=list(project.rglob('*syn.rpt*'))
        if cp.returncode or not reports:
            print(cp.stdout.decode('utf-8','replace')[-3000:]);print(cp.stderr.decode('utf-8','replace'))
            raise RuntimeError(f'{name}: synthesis exit={cp.returncode}, reports={reports}')
        for i,path in enumerate(reports):(out/f'{name}-{i}-syn.rpt.txt').write_bytes(path.read_bytes())
        for path in reports[0].parent.glob('*_syn_resource.html'):
            (out/(name+'-hierarchy.html')).write_bytes(path.read_bytes())
        results.append(dict(variant=name,exit=cp.returncode,reports=[str(p) for p in reports]))
        (out/'results.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
        metrics.append(resource_metrics(name,reports[0]))
        (out/'resource-metrics.json').write_text(json.dumps(metrics,indent=2),encoding='utf-8')
        print(json.dumps(results[-1]),flush=True)

if __name__=='__main__':main()
