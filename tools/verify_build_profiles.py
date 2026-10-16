"""Exercise profile setup in real Gowin; elaborate RTL; mock programming only.

Does not synthesize, route, run the full simulation gate, or touch hardware.
"""
from pathlib import Path
import argparse, json, os, shutil, subprocess, sys, time


def main():
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    parser = argparse.ArgumentParser()
    parser.add_argument('--gw-sh', default=r'E:\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\bin\gw_sh.exe')
    parser.add_argument('--iverilog', default=r'C:\iverilog\bin\iverilog.exe')
    parser.add_argument('--out', type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    source = root/'output/handoff_milestone2_20261008/source'
    work = root/'tmp/build-profiles-verification-20261016'/str(time.time_ns())
    out = args.out or root/'docs/evidence/FPGA-构建入口-20261016-v0.1'
    work.mkdir(parents=True, exist_ok=True)
    out.mkdir(parents=True, exist_ok=True)
    rows = []

    def execute(name, command, *, env=None, expect=0, cwd=None):
        cp = subprocess.run(list(map(str, command)), cwd=cwd or root, env=env,
                            capture_output=True, timeout=90)
        (out/(name+'.log')).write_bytes(cp.stdout+cp.stderr)
        ok = cp.returncode == expect if expect is not None else cp.returncode != 0
        rows.append(dict(test=name, exit=cp.returncode, passed=ok))
        (out/'results.json').write_text(json.dumps(rows, ensure_ascii=False, indent=2), encoding='utf-8')
        print(f'{name}: exit={cp.returncode}, passed={ok}', flush=True)
        if not ok:
            raise AssertionError(cp.stdout.decode('utf-8','replace')+cp.stderr.decode('utf-8','replace'))
        return cp

    # Actual Gowin project creation/add_file/options; replace only run so this
    # remains a configuration test, without launching synthesis or PnR.
    for profile, entry, top in [('debug','build_top_integrated.tcl','top_dbg_build'),
                                ('standard','build_top_i2s_std.tcl','top_std_build')]:
        run_dir = work/('actual-'+profile)
        manifest = work/(profile+'-files.txt')
        harness = work/(profile+'.tcl')
        harness.write_text('''rename add_file vendor_add_file
proc add_file {path} {
    global files
    lappend files $path
    vendor_add_file $path
}
proc run {args} { puts "FLOW_SETUP_PASS (synthesis intentionally omitted)" }
set files {}
set ::env(FPGA_BUILD_RUN_DIR) {%s}
source {%s}
set fh [open {%s} w]
puts $fh [join $files \\n]
close $fh
''' % (run_dir.as_posix(), (source/'build'/entry).as_posix(), manifest.as_posix()), encoding='utf-8')
        execute(profile+'-gowin-setup', [args.gw_sh,harness])
        assert (run_dir/'instrument/instrument.gprj').is_file(), 'Gowin output hierarchy changed'
        paths = manifest.read_text().splitlines()
        assert len(paths) == len(set(paths))
        for required in ['mcp3208_spi.v','pressure_bend.v','shared_wavetable_engine.v','global_crossfade.v']:
            assert any(Path(p).name == required for p in paths), required
        rtl = [p for p in paths if Path(p).suffix == '.v']
        execute(profile+'-rtl-elaboration', [args.iverilog,'-g2012','-DSIMULATION','-I',source,
            '-s',top,'-o',work/(profile+'.vvp'),*rtl,source/'sim/gowin_prom_model.v'], cwd=source)
        (out/(profile+'-sources.txt')).write_text('\n'.join(paths)+'\n',encoding='utf-8')

    fixture = work/'fixture/source'
    fixture.mkdir(parents=True,exist_ok=True)
    for name in ['rtl','constraints']:
        shutil.copytree(source/name, fixture/name, dirs_exist_ok=True)
    build = fixture/'build'
    build.mkdir(exist_ok=True)
    for path in (source/'build').iterdir():
        if path.is_file() and path.suffix in ['.ps1','.tcl','.list','.tsv']:
            shutil.copy2(path,build/path.name)
    shutil.copytree(source/'build/isolated',build/'isolated',dirs_exist_ok=True)
    (fixture/'sim').mkdir(exist_ok=True)
    gate = fixture/'sim/run_simulation.ps1'
    gate.write_text("Set-Content -LiteralPath (Join-Path $PSScriptRoot 'gate-called.txt') -Value yes\nexit 0\n")
    fake = work/'mock-gw.ps1'
    fake.write_text('''param([string]$Entry)
if ($env:FPGA_TEST_BUILD_FAIL -eq '1') { exit 9 }
$pnr = Join-Path $env:FPGA_BUILD_RUN_DIR 'instrument/impl/pnr'
New-Item -ItemType Directory -Path $pnr -Force | Out-Null
Set-Content -LiteralPath (Join-Path $pnr 'instrument.fs') -Value 'MOCK BITSTREAM - NOT FOR HARDWARE'
exit 0
''')
    programmer = work/'mock-programmer.ps1'
    programmer.write_text('''Set-Content -LiteralPath $env:FPGA_TEST_PROGRAM_ARGS -Value ($args -join '|')
exit 0
''')
    base = ['powershell.exe','-NoProfile','-ExecutionPolicy','Bypass','-File']
    env = dict(os.environ, FPGA_TEST_PROGRAM_ARGS=str(work/'program-args.txt'))
    for profile in ['debug','standard']:
        execute(profile+'-wrapper-build', [*base,build/'build.ps1','-Profile',profile,'-GwSh',fake],env=env)
        receipt = json.loads((build/'receipts'/f'{profile}.json').read_text(encoding='utf-8-sig'))
        execute(profile+'-program-selection', [*base,build/'program_sram.ps1','-Profile',profile,
            '-Programmer',programmer],env=env)
        assert receipt['Bitstream'] in (work/'program-args.txt').read_text()
        assert (fixture/'sim/gate-called.txt').is_file(), 'Default simulation gate was bypassed'
    # Existing legacy files must never win over the selected profile receipt.
    legacy = fixture/'impl/pnr/instrument.fs'
    legacy.parent.mkdir(parents=True,exist_ok=True)
    legacy.write_text('OLD BITSTREAM')
    changed = fixture/'rtl/top.v'
    changed.write_bytes(changed.read_bytes()+b'\n// changed after build\n')
    (work/'program-args.txt').unlink()
    execute('changed-source-rejected', [*base,build/'program_sram.ps1','-Profile','standard',
        '-Programmer',programmer],env=env,expect=None)
    assert not (work/'program-args.txt').exists()
    execute('failed-build-reported', [*base,build/'build.ps1','-Profile','debug','-GwSh',fake],
        env=dict(env,FPGA_TEST_BUILD_FAIL='1'),expect=None)
    assert not (build/'receipts/debug.json').exists()
    execute('legacy-fallback-rejected', [*base,build/'program_sram.ps1','-Profile','debug',
        '-Programmer',programmer],env=env,expect=None)
    assert not (work/'program-args.txt').exists()
    execute('explicit-historical-file', [*base,build/'program_sram.ps1','-FsFile',legacy,
        '-Programmer',programmer],env=env)
    assert str(legacy) in (work/'program-args.txt').read_text()
    gate.write_text('exit 1\n')
    (work/'program-args.txt').unlink()
    execute('failed-simulation-gate-rejected', [*base,build/'program_sram.ps1','-FsFile',legacy,
        '-Programmer',programmer],env=env,expect=None)
    assert not (work/'program-args.txt').exists()
    print(f'PASS: {len(rows)} checks. Temporary fixtures: {work}',flush=True)


if __name__ == '__main__':
    main()
