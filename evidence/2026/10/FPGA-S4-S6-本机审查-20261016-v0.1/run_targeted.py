"""Reproduce the S4-S6 review without invoking the programming gate.

Usage: python run_targeted.py --source <handoff/source> [--out <evidence>]
All generated executables live under workspace tmp/ and are removable.
"""
from pathlib import Path
import argparse
import json
import os
import subprocess
import time
import sys


def main():
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    p = argparse.ArgumentParser()
    p.add_argument('--source', type=Path, required=True)
    p.add_argument('--out', type=Path, default=Path(__file__).resolve().parent)
    p.add_argument('--iverilog', default=r'C:\iverilog\bin\iverilog.exe')
    p.add_argument('--vvp', default=r'C:\iverilog\bin\vvp.exe')
    p.add_argument('--only', nargs='+')
    a = p.parse_args()
    source, out = a.source.resolve(), a.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    workspace = next(x for x in out.parents if (x / 'AGENTS.md').is_file())
    build = workspace / 'tmp' / 's4s6-review-20261016' / 'sim-build'
    build.mkdir(parents=True, exist_ok=True)
    rtl = list((source / 'rtl' / 'audio').glob('*.v')) + [source / 'rtl' / 'top.v']
    models = [source / 'sim' / 'gowin_prom_model.v', source / 'sim' / 'mcp3208_model.v']
    names = ['tb_mcp3208_spi', 'tb_pressure_bend', 'tb_s6_audio',
             'tb_s6_rom_prim', 'tb_shared_engine', 'tb_top_i2s',
             'tb_review_engine', 'tb_review_top']
    results_file = out / 'simulation_results.json'
    results = json.loads(results_file.read_text(encoding='utf-8')) if a.only and results_file.exists() else []
    env = dict(os.environ, PYTHONIOENCODING='utf-8')
    for name in names:
        if a.only and name not in a.only:
            continue
        tb = (out if name.startswith('tb_review') else source / 'sim') / (name + '.v')
        exe = build / (name + '.vvp')
        command = [a.iverilog, '-g2012', '-DSIMULATION', '-Wall', '-I', str(source),
                   '-s', name, '-o', str(exe), str(tb)] + [str(x) for x in rtl + models]
        start = time.monotonic()
        comp = subprocess.run(command, cwd=source, env=env, capture_output=True)
        (out / (name + '-compile.log')).write_bytes(comp.stdout + comp.stderr)
        run = None
        if comp.returncode == 0:
            run = subprocess.run([a.vvp, str(exe)], cwd=source, env=env,
                                 capture_output=True, timeout=180)
            (out / (name + '.log')).write_bytes(run.stdout + run.stderr)
        item = dict(test=name, compile_exit=comp.returncode,
                    simulation_exit=None if run is None else run.returncode,
                    seconds=round(time.monotonic() - start, 3), command=command,
                    cwd=str(source))
        results = [x for x in results if x['test'] != name] + [item]
        results_file.write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding='utf-8')
        print(json.dumps({k:v for k,v in item.items() if k not in ('command','cwd')}, ensure_ascii=False), flush=True)
        if run is not None:
            print(run.stdout.decode('utf-8', 'replace')[-1600:], flush=True)
    return int(any(x['compile_exit'] != 0 or x['simulation_exit'] != 0 for x in results))


if __name__ == '__main__':
    raise SystemExit(main())
