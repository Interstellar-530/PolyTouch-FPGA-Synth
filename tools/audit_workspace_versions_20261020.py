"""Inventory source copies without selecting a version by timestamp alone."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from datetime import datetime, timezone
from pathlib import Path

KEY_NAMES = {
    'top.v', 'shared_wavetable_engine.v', 'global_crossfade.v', 'uart_ctrl.v',
    'voice_transition.v', 'hid_keymap.v', 'host_kbd_input.v', 'ch9350_rx.v',
    'gowin_prom_piano_bank.v', 'gowin_prom_guitar_bank.v', 'KeyboardCore.cs',
    'KeyboardWindow.cs', 'gen_epiano_bank.py', 'gen_guitar_samples_bank.py',
    'top_std27_build.v', 'primer20k_i2s_27m.cst', 'run_simulation.ps1',
}
SKIP = {'.git', 'node_modules', '__pycache__', '.venv-gowin-mcp',
        '.venv-docconvert', '.venv-audio-analysis', 'agent-runtime', 'vendor',
        'tessdata', '.venv', 'venv', 'toolchains'}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    root = args.root.resolve()
    rows = []
    visited = 0
    for directory, folders, files in os.walk(root):
        folders[:] = sorted(x for x in folders if x not in SKIP)
        for name in sorted(files):
            visited += 1
            if name not in KEY_NAMES:
                continue
            path = Path(directory) / name
            stat = path.stat()
            rows.append({
                'path': path.relative_to(root).as_posix(), 'name': name,
                'bytes': stat.st_size,
                'modified_utc': datetime.fromtimestamp(stat.st_mtime, timezone.utc).isoformat(),
                'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
            })
    rows.sort(key=lambda row: (row['name'], row['modified_utc'], row['path']))
    result = {'scanned_files': visited, 'matched_copies': len(rows),
              'excluded_runtime_directories': sorted(SKIP), 'copies': rows}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    production = [row for row in rows if row['path'].startswith('output/handoff_milestone2_20261008/source/')
                  or row['path'].startswith('tools/')]
    print(json.dumps({'scanned_files': visited, 'matched_copies': len(rows),
                      'canonical_candidates': production}, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
