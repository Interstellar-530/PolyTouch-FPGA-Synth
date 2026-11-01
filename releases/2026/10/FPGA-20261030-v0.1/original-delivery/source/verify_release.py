"""Verify byte-preserved release, build provenance and final validation evidence."""
from pathlib import Path
import hashlib, json, sys

BASE = Path(__file__).resolve().parents[1]
EXPECTED_FS = 'b4dd1b5d1a5d89ba871e34f4e230a85fbe3c92c486934f57dcc811bdb2edf003'

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def read_json(relative):
    return json.loads((BASE/relative).read_text(encoding='utf-8-sig'))

if '--write-checksums' in sys.argv:
    paths = sorted(p for p in BASE.rglob('*') if p.is_file() and p.name != 'checksums.sha256')
    (BASE/'checksums.sha256').write_text(''.join(digest(p)+'  '+p.relative_to(BASE).as_posix()+'\n' for p in paths), encoding='utf-8')

rows = (BASE/'checksums.sha256').read_text(encoding='utf-8-sig').splitlines()
listed=set()
for row in rows:
    expected, name=row.split('  ', 1)
    path=(BASE/name).resolve()
    assert path.is_relative_to(BASE), name
    assert path.is_file() and digest(path)==expected, 'Checksum mismatch: '+name
    listed.add(name)
actual={p.relative_to(BASE).as_posix() for p in BASE.rglob('*') if p.is_file() and p.name!='checksums.sha256'}
assert actual==listed, 'Manifest file list differs'
receipt=read_json('evidence/build/hdmi.json')
assert receipt['BitstreamSha256']==EXPECTED_FS==digest(BASE/'target/instrument.fs')
assert receipt['Profile']=='hdmi'
for item in receipt['Inputs']:
    normalized=item['Path'].replace('\\','/')
    relative=normalized.split('/output/handoff_milestone2_20261008/source/',1)[1]
    assert digest(BASE/'source/verified-inputs'/relative)==item['Sha256'].lower(), relative
fast=read_json('evidence/rtl/fast-gate-result.json')
board=read_json('evidence/rtl/board-gate-result.json')
assert fast['Passed'] and board['Passed']
assert len(fast['Results'])==7 and len(board['Results'])==1
assert all(r['Passed'] for r in fast['Results']+board['Results'])
assert 'max_release_ms=3.499998' in (BASE/'evidence/rtl/tb_fsr_pedal_latency.run.log').read_text()
assert read_json('evidence/sram/program-result.json')['ReadbackMatched']
assert read_json('evidence/flash/flash-result.json')['ProgramAndVerifyPassed']
assert read_json('evidence/flash/settled-result.json')['SettledReadbackMatched']
assert read_json('evidence/ui/ui-pixel-check.json')['mismatches']==0
assert all(not r['clipped'] and not r['panelOverflow'] for r in read_json('evidence/layout-check.json'))
print(json.dumps(dict(status='PASS',files=len(rows),build_inputs=len(receipt['Inputs']),rtl_checks=8,
                      flash_user_code='0x00002626',bitstream_sha256=EXPECTED_FS),indent=2))
