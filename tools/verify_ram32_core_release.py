"""Verify archived Ram32 simulation fingerprints and actual implementation reports."""
import argparse
import hashlib
import json
from pathlib import Path
from bs4 import BeautifulSoup

p = argparse.ArgumentParser()
p.add_argument('--archive', type=Path, required=True)
a = p.parse_args().archive.resolve()
src = a / 'source/after'
checks = {}
for name, count in [('ram32', 5), ('quick', 18), ('compat', 4)]:
    result = json.loads((a / f'evidence/{name}/gate-result.json').read_text(encoding='utf-8-sig'))
    assert result['Passed'] and not any(result['ChangedDuringRun'] or []), name
    assert len(result['Results']) == count and all(r['Passed'] for r in result['Results']), name
    for row in result['Inputs']:
        path = src / row['Path'].replace('\\', '/')
        assert path.is_file(), str(path)
        assert hashlib.sha256(path.read_bytes()).hexdigest().lower() == row['SHA256'].lower(), str(path)
    checks[name] = {'passed': True, 'checks': count, 'seconds': result['ElapsedSeconds'],
                    'input_files': len(result['Inputs'])}
timing = BeautifulSoup((a / 'target/pnr/ram32c_tr_content.html').read_text(), 'html.parser')
tables = timing.find_all('table')
summary = {}
for row in tables[1].find_all('tr'):
    cells = [c.get_text(' ', strip=True) for c in row.find_all(['td', 'th'])]
    if len(cells) == 2:
        summary[cells[0]] = cells[1]
for key in ['Numbers of Setup Violated Endpoints', 'Numbers of Hold Violated Endpoints']:
    assert int(summary[key]) == 0, (key, summary[key])
paths = []
for table in tables:
    if table.get_text(' ', strip=True).startswith('Path Number Path Slack'):
        for row in table.find_all('tr')[1:]:
            cells = [c.get_text(' ', strip=True) for c in row.find_all(['td', 'th'])]
            if len(cells) == 9:
                paths.append(cells)
assert paths and min(float(x[1]) for x in paths) >= 0
checks['timing'] = summary
checks['minimum_reported_path_slack_ns'] = min(float(x[1]) for x in paths)
checks['bitstream_sha256'] = hashlib.sha256((a / 'target/pnr/ram32c.fs').read_bytes()).hexdigest()
checks['scope'] = '32-voice core prototype only; no board pin mapping or hardware programming'
(a / 'validation.json').write_text(json.dumps(checks, indent=2), encoding='utf-8')
print(json.dumps(checks, indent=2))
