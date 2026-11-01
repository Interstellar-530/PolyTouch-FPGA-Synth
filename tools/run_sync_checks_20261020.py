"""Short, read-only product checks before publishing the current source snapshot."""
from __future__ import annotations
import argparse
import hashlib
import json
import subprocess
import tempfile
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    source = root / 'source'
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    rows = []
    audio = sorted((source / 'rtl/audio').glob('*.v'))
    models = [source / 'sim/gowin_prom_model.v', source / 'sim/mcp3208_model.v']
    iverilog = Path('C:/iverilog/bin/iverilog.exe')
    vvp = Path('C:/iverilog/bin/vvp.exe')
    inputs = audio + [source / 'rtl/top.v'] + models

    def run(name, command, cwd=source):
        try:
            result = subprocess.run([str(x) for x in command], cwd=cwd,
                                    capture_output=True, timeout=150)
            log = result.stdout + result.stderr
            code = result.returncode
        except subprocess.TimeoutExpired as error:
            log = (error.stdout or b'') + (error.stderr or b'') + b'\nTIMEOUT\n'
            code = 124
        (out / f'{name}.log').write_bytes(log)
        rows.append({'check': name, 'exit': code, 'passed': code == 0})
        print(f'{name}: exit={code}', flush=True)
        return code == 0

    temporary_parent = root / 'tmp'
    temporary_parent.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='github-sync-checks-', dir=temporary_parent) as temporary:
        build = Path(temporary)
        for name in ['tb_key_gain', 'tb_host_kbd', 'tb_top_switch', 'tb_top_pitch8']:
            executable = build / f'{name}.vvp'
            command = [iverilog, '-g2012', '-DSIMULATION', '-I', '.', '-s', name,
                       '-o', executable, source / f'sim/{name}.v', *inputs]
            if run(name + '-compile', command):
                run(name, [vvp, executable])
        for name in ['top_dbg8_build', 'top_std27_build']:
            run(name + '-elaboration', [iverilog, '-g2012', '-DSIMULATION', '-I', '.',
                '-s', name, '-o', build / f'{name}.vvp',
                source / f'build/isolated/{name}.v', *inputs])
    run('pc-keyboard-selftest', ['powershell.exe', '-NoProfile', '-ExecutionPolicy',
        'Bypass', '-File', root / 'tools/serial_keyboard/keyboard.ps1', '-SelfTest'], root)
    hashes = {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
              for p in inputs}
    result = {'scope': 'four targeted RTL benches, two top elaborations, PC self-test; no hardware',
              'checks': rows, 'source_sha256': hashes,
              'passed': all(row['passed'] for row in rows)}
    (out / 'checks.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    raise SystemExit(0 if result['passed'] else 1)


if __name__ == '__main__':
    main()
