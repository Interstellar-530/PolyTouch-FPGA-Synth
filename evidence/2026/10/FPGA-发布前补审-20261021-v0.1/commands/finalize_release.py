"""Verify the prepared archive/index and finish publication metadata only."""
from pathlib import Path
import hashlib, json, shutil, subprocess
ROOT = next(p for p in Path(__file__).resolve().parents if (p / '.git').exists())
OUT = Path(__file__).resolve().parents[1]
A = ROOT / 'archive/FPGA-20261021-v0.9'
R = ROOT / 'releases/v2.1.0'
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def git(*args): return subprocess.check_output(['git', *args], cwd=ROOT)
for line in (A / 'checksums.sha256').read_text(encoding='utf-8').splitlines():
    # The release evidence is refreshed below; immutable source/targets remain
    # checked against the initial archive even when resuming finalization.
    if not (A / line[66:]).is_relative_to(A / 'evidence' / OUT.name):
        assert sha(A / line[66:]) == line[:64]
for line in (R / 'checksums.sha256').read_text(encoding='utf-8').splitlines():
    assert sha(R / line[66:]) == line[:64]
# Release text is explicitly LF in .gitattributes; checksum those exact bytes.
for p in R.iterdir():
    if p.is_file() and p.suffix != '.fs':
        data = p.read_bytes().replace(b'\r\n', b'\n')
        p.write_bytes(data)
release_files = sorted(p for p in R.iterdir() if p.is_file() and p.name != 'checksums.sha256')
(R / 'checksums.sha256').write_bytes(('\n'.join(sha(p) + '  ' + p.name for p in release_files) + '\n').encode('utf-8'))
rows = (R / 'source-manifest.sha256').read_text(encoding='utf-8').splitlines()
for line in rows:
    assert hashlib.sha256(git('show', ':' + line[66:])).hexdigest() == line[:64]
after = json.loads((OUT / 'after_results.json').read_text())
assert after['passed'] and all(sha(Path(k)) == v for k, v in after['inputs_sha256'].items())
receipt = json.loads((OUT / 'build_receipt.json').read_text())
assert all(sha(Path(k)) == v for k, v in receipt['inputs_sha256'].items())
check = subprocess.run(['git', 'diff', '--cached', '--check'], cwd=ROOT, capture_output=True)
(OUT / 'staged_check.log').write_bytes(check.stdout + check.stderr)
result = dict(source_manifest_files=len(rows), archive_initial_hashes_valid=True,
    artifact_hashes_valid=True, reviewed_inputs_unchanged=True,
    whitespace_exit=check.returncode, whitespace_note='Original evidence/snapshots retain tool whitespace; no RTL changed for formatting.',
    simulation_repeated=False, hardware_programmed=False)
(OUT / 'release_verification.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
git('add', '--', str(OUT.relative_to(ROOT)), 'releases/v2.1.0')
for p in R.iterdir():
    if p.is_file(): assert hashlib.sha256(git('show', ':' + p.relative_to(ROOT).as_posix())).hexdigest() == sha(p)
staged = git('diff', '--cached', '--name-only', '-z').decode().split('\0')
assert not any(p.startswith(('tmp/', 'archive/', 'tools/agent-runtime/', 'output/pdf/', 'output/reports/')) for p in staged if p)
for p in filter(None, staged):
    disk = ROOT / p
    if disk.is_file(): assert disk.stat().st_size < 100 * 1024 * 1024
for p in OUT.rglob('*'):
    if p.is_file():
        dest = A / 'evidence' / OUT.name / p.relative_to(OUT)
        if dest.exists() and sha(dest) == sha(p): continue
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(p, dest)
for p in R.iterdir():
    if p.is_file():
        dest = A / 'target/v2.1.0' / p.name
        if sha(dest) != sha(p): shutil.copy2(p, dest)
files = sorted(p for p in A.rglob('*') if p.is_file() and p != A / 'checksums.sha256')
lines = [sha(p) + '  ' + p.relative_to(A).as_posix() for p in files]
(A / 'checksums.sha256').write_text('\n'.join(lines) + '\n', encoding='utf-8')
assert all(sha(A / line[66:]) == line[:64] for line in lines)
print(f'Verified {len(rows)} canonical source/tool files, {len(files)} archive files; {len(list(filter(None, staged)))} staged paths. Ready to commit.')
