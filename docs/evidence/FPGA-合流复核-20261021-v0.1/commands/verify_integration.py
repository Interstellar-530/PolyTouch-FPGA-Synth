"""Bounded checks of the integrated product; this is not the full flashing gate."""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import subprocess

OUT = Path(__file__).resolve().parents[1]
ROOT = next((p for p in Path(__file__).resolve().parents if (p / '.git').exists()), OUT.parent)
SOURCE = (OUT.parent / 'source') if (OUT.parent / 'source').is_dir() else ROOT / 'output/handoff_milestone2_20261008/source'
TOOL_ROOT = OUT.parent if (OUT.parent / 'source').is_dir() else ROOT
WORK = ROOT / 'tmp/github-integration-20261021-v01/focused'
IVERILOG = Path('C:/iverilog/bin/iverilog.exe')
VVP = Path('C:/iverilog/bin/vvp.exe')
ROWS = []


def run(name, args, cwd=SOURCE, timeout=60):
    try:
        result = subprocess.run([str(x) for x in args], cwd=cwd, capture_output=True, timeout=timeout)
        data, code = result.stdout + result.stderr, result.returncode
    except subprocess.TimeoutExpired as error:
        data = (error.stdout or b'') + (error.stderr or b'') + b'\nTIMEOUT\n'
        code = 124
    (OUT / f'{name}.log').write_bytes(data)
    row = dict(check=name, exit=code, passed=code == 0)
    ROWS.append(row)
    print(f'{name}: exit={code}', flush=True)
    return code, data


def switch_smoke(inputs):
    # The original 4500-frame soak exceeded the requested short-check budget.
    # Preserve every assertion and real UART byte; only reduce the three
    # post-note waiting windows. This checks control behavior, not long audio.
    text = (SOURCE / 'sim/tb_top_switch.v').read_text(encoding='utf-8')
    if text.count('wait_frames(1500);') != 3:
        raise RuntimeError('switch bench changed; review the short-window derivation')
    bench = WORK / 'tb_top_switch_smoke.v'
    bench.write_text(text.replace('wait_frames(1500);', 'wait_frames(16);'), encoding='utf-8')
    binary = WORK / 'tb_top_switch_smoke.vvp'
    code, _ = run('tb_top_switch_smoke-compile', [IVERILOG, '-g2012', '-DSIMULATION',
                  '-I', '.', '-s', 'tb_top_switch', '-o', binary, bench, *inputs])
    if code == 0:
        code, data = run('tb_top_switch_smoke', [VVP, binary], timeout=20)
        ROWS[-1]['passed'] = code == 0 and b'PASS' in data
        ROWS[-1]['scope'] = 'all original assertions; each 1500-frame wait reduced to 16; no long audio claim'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--switch-only', action='store_true')
    args = parser.parse_args()
    WORK.mkdir(parents=True, exist_ok=True)
    inputs = sorted((SOURCE / 'rtl/audio').glob('*.v')) + [SOURCE / 'rtl/top.v',
              SOURCE / 'sim/gowin_prom_model.v', SOURCE / 'sim/mcp3208_model.v']
    tests = ['tb_key_gain', 'tb_host_kbd', 'tb_top_switch', 'tb_top_pitch8',
             'tb_engine8_pitch', 'tb_mute_slew', 'tb_wide_master', 'tb_piano_bank',
             'tb_bright_banks', 'tb_guitar_bank']
    if args.switch_only:
        switch_smoke(inputs)
        (OUT / 'focused_switch_retry.json').write_text(json.dumps(
            dict(checks=ROWS, passed=all(x['passed'] for x in ROWS)), indent=2) + '\n', encoding='utf-8')
        raise SystemExit(0 if all(x['passed'] for x in ROWS) else 1)
    for name in tests:
        if name == 'tb_top_switch':
            switch_smoke(inputs)
            continue
        binary = WORK / f'{name}.vvp'
        code, _ = run(name + '-compile', [IVERILOG, '-g2012', '-DSIMULATION', '-I', '.',
                         '-s', name, '-o', binary, SOURCE / f'sim/{name}.v', *inputs])
        if code == 0:
            code, data = run(name, [VVP, binary])
            if code == 0 and b'PASS' not in data:
                ROWS[-1]['passed'] = False
                ROWS[-1]['reason'] = 'missing PASS marker'
    for name in ['top_dbg8usb_build', 'top_std27_build']:
        run(name + '-elaboration', [IVERILOG, '-g2012', '-DSIMULATION', '-I', '.',
             '-s', name, '-o', WORK / f'{name}.vvp', SOURCE / f'build/isolated/{name}.v', *inputs])

    # Exercise the new preflight using an isolated fixture; real sources stay in place.
    fixture = WORK / 'missing-bench/source'
    (fixture / 'sim').mkdir(parents=True, exist_ok=True)
    (fixture / 'rtl/audio').mkdir(parents=True, exist_ok=True)
    gate = fixture / 'sim/run_simulation.ps1'
    gate.write_bytes((SOURCE / 'sim/run_simulation.ps1').read_bytes())
    for bench in (SOURCE / 'sim').glob('*.v'):
        if bench.name != 'tb_key_gain.v':
            (fixture / 'sim' / bench.name).write_text('', encoding='ascii')
    code, data = run('missing_bench_rejected', ['powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass',
         '-File', gate, '-BuildDir', WORK / 'fault_build', '-AudioCaptureDir', WORK / 'fault_capture',
         '-MetricsDir', WORK / 'fault_metrics'], cwd=ROOT, timeout=20)
    ROWS[-1]['passed'] = code == 1 and b'tb_key_gain.v' in data and b'=== ' not in data
    ROWS[-1]['expected_exit'] = 1

    # Rebuild from versioned HEX without downloading the original wave sample.
    spec = importlib.util.spec_from_file_location('piano_generator', TOOL_ROOT / 'tools/gen_piano_prom.py')
    generator = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(generator)
    generator.AUDIO = SOURCE / 'rtl/audio'
    generator.HEX = generator.AUDIO / 'epiano_bank_all.hex'
    generator.OUT = WORK / 'piano_regenerated.v'
    generator.main()
    actual = (SOURCE / 'rtl/audio/gowin_prom_piano_bank.v').read_text(encoding='ascii').splitlines()[1:]
    generated = generator.OUT.read_text(encoding='ascii').splitlines()[1:]
    ROWS.append(dict(check='piano_regenerated_body', passed=(actual == generated),
                      words=len(generator.HEX.read_text().split()), comparison='exclude first provenance comment only'))
    hashes = {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
    result = dict(scope='10 RTL benches, two profile elaborations, missing-bench rejection, ROM reproduction',
                  full_gate_completed=False, hardware_programmed=False,
                  checks=ROWS, inputs_sha256=hashes, passed=all(x['passed'] for x in ROWS))
    (OUT / 'focused_checks.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    raise SystemExit(0 if result['passed'] else 1)


if __name__ == '__main__':
    main()
