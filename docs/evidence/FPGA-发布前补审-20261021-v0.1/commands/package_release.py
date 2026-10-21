"""Explicit release staging, canonical source manifest, bounded cleanup and archive."""
from pathlib import Path
import hashlib, json, shutil, stat, subprocess
ROOT = next(p for p in Path(__file__).resolve().parents if (p / '.git').exists())
OUT = Path(__file__).resolve().parents[1]
REL = Path('output/handoff_milestone2_20261008/source')
SRC = ROOT / REL
RELEASE = ROOT / 'releases/v2.1.0'
ARCHIVE = ROOT / 'archive/FPGA-20261021-v0.9'
assert not ARCHIVE.exists(), 'Never overwrite an archive'
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p, s):
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(s, encoding='utf-8')
def git(*args): return subprocess.check_output(['git', *args], cwd=ROOT)
def copy(a, b):
    b.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(a, b)
after = json.loads((OUT / 'after_results.json').read_text())
assert after['passed'] and all(sha(Path(k)) == v for k, v in after['inputs_sha256'].items())
build = json.loads((OUT / 'build_receipt.json').read_text())
assert all(sha(Path(k)) == v for k, v in build['inputs_sha256'].items())

roots = [ROOT / 'tmp' / n for n in ['prepublish-review-20261021-v01', 'prepublish-ram32-pnr-20261021-v01', 'prepublish-ram32-pnr-20261021-v02']]
inventory = []
for root in roots:
    assert root.resolve().parent == (ROOT / 'tmp').resolve()
    assert not root.is_symlink() and not root.is_junction()
    paths = list(root.rglob('*')) if root.exists() else []
    assert all(p.resolve().is_relative_to(root.resolve()) and not p.is_symlink() and not p.is_junction() for p in paths)
    inventory.append(dict(root=str(root.resolve()), files=[str(p.relative_to(root)) for p in paths if p.is_file()]))
write(OUT / 'cleanup_inventory.json', json.dumps(inventory, ensure_ascii=False, indent=2) + '\n')
print('Cleanup targets: ' + json.dumps([str(p) for p in roots], ensure_ascii=False), flush=True)
for root in roots:
    if root.exists():
        for p in root.rglob('*'):
            if p.is_file(): p.chmod(p.stat().st_mode | stat.S_IWRITE)
        shutil.rmtree(root)
assert all(not p.exists() for p in roots)
write(OUT / 'packaging.json', json.dumps(dict(archive=str(ARCHIVE), temporary_roots_removed=True,
    existing_tools_and_history_preserved=True, full_gate=False, hardware_programmed=False,
    production_input_count=192, prototype_input_count=21), indent=2) + '\n')

scope = ['.gitattributes', 'README.md', REL.as_posix(), 'docs/releases/v2.0.0.md', 'docs/releases/v2.0.1.md',
    'docs/releases/v2.1.0.md', 'docs/版本索引与文件地图-20261014-v0.1.md', 'releases/v2.1.0']
scope += [str(p.relative_to(ROOT)) for p in (ROOT / 'docs/reviews').glob('*20261021*') if p.is_file()]
scope += [str(p.relative_to(ROOT)) for p in (ROOT / 'docs/evidence').iterdir() if p.is_dir() and '20261021' in p.name]
scope += ['tools/' + n for n in ['gen_epiano_bank.py', 'gen_piano_prom.py', 'gen_guitar_bank.py',
    'gen_guitar_samples_bank.py', 'verify_build_profiles.py', 'render_bank_ab.py']]
stage = subprocess.run(['git', 'add', '--', *scope], cwd=ROOT, capture_output=True)
(OUT / 'git_add.log').write_bytes(stage.stdout + stage.stderr)
assert stage.returncode == 0
indexed = git('ls-files', '-s', '-z', '--', REL.as_posix(), *[x for x in scope if x.startswith('tools/')]).split(b'\0')
entries = []
for row in filter(None, indexed):
    info, path = row.split(b'\t', 1)
    mode, oid, stage_no = info.split()
    assert stage_no == b'0' and mode in (b'100644', b'100755')
    entries.append((path.decode('utf-8'), oid.decode()))
proc = subprocess.Popen(['git', 'cat-file', '--batch'], cwd=ROOT, stdin=subprocess.PIPE, stdout=subprocess.PIPE)
lines = []
for path, oid in entries:
    proc.stdin.write((oid + '\n').encode()); proc.stdin.flush()
    header = proc.stdout.readline().split(); assert header[1] == b'blob'
    data = proc.stdout.read(int(header[2])); assert proc.stdout.read(1) == b'\n'
    lines.append(hashlib.sha256(data).hexdigest() + '  ' + path)
proc.stdin.close(); assert proc.wait() == 0
write(RELEASE / 'source-manifest.sha256', '\n'.join(lines) + '\n')
files = sorted(p for p in RELEASE.iterdir() if p.is_file() and p.name != 'checksums.sha256')
write(RELEASE / 'checksums.sha256', '\n'.join(sha(p) + '  ' + p.name for p in files) + '\n')

ARCHIVE.mkdir(parents=True)
for path, _ in entries:
    p = ROOT / path
    copy(p, ARCHIVE / ('source' if p.is_relative_to(SRC) else 'tools') / (p.relative_to(SRC) if p.is_relative_to(SRC) else p.name))
for p in (ROOT / 'docs/evidence').iterdir():
    if p.is_dir() and '20261021' in p.name: shutil.copytree(p, ARCHIVE / 'evidence' / p.name)
for p in (ROOT / 'docs/reviews').glob('*20261021*'):
    if p.is_file(): copy(p, ARCHIVE / 'target/reviews' / p.name)
shutil.copytree(RELEASE, ARCHIVE / 'target/v2.1.0')
copy(OUT / 'ram32.fs', ARCHIVE / 'target/ram32_instrument_prototype.fs')
copy(ROOT / 'README.md', ARCHIVE / 'target/README.md')
copy(ROOT / 'docs/releases/v2.1.0.md', ARCHIVE / 'CHANGELOG.md')
write(ARCHIVE / 'MANIFEST.md', '''# FPGA-20261021-v0.9

2026-10-21 六项优化与发布前补审的最终 v2.1.0 快照。source/ 保存唯一工程源、HEX、约束、测试与构建入口；tools/ 保存本次生成、验证、试听工具。target/ 包含生产 8 声部 PT8211 位流、独立 32 声部原型位流、审核报告和版本说明；evidence/ 保存当天逐项实现/审核、首次失败及修正后证据。CHANGELOG.md 为完整变更和验证边界。

checksums.sha256 使用归档原始字节；target/v2.1.0/source-manifest.sha256 使用 Git 暂存区规范化后的源码字节，可能与 Windows 工作区换行不同。21 个原型输入和 192 个生产输入核对通过。本轮未烧录、未声称完整长门禁通过。32 声部晶振及板级接线后续完成。
''')
write(ARCHIVE / 'REPRODUCE.md', '''# 复现

从项目根目录按 README 调用 source/build/build.ps1 -Profile debug8usb（或 standard27），需本机 Gowin EDA。定向补审运行 docs/evidence/FPGA-发布前补审-20261021-v0.1/commands/run_checks.py，需 Python 与 C:/iverilog/bin；--before 可重现保存的旧错误。build_review.py 独立实现 ram32_top，位流无板级 CST。全部输入、命令与报告在 evidence/。已有证据无需反复运行。

source/ 可恢复到原唯一工程目录后重建，路径变化或换行变化后重新生成构建凭据。各项 before/、audit_changes.patch 及 Git v2.0.0 提供回退依据。正式烧录前运行项目完整 RTL 仿真门禁。本次三个明确 tmp 子目录已清理，运行环境与历史构建保留。
''')
archive_files = sorted(p for p in ARCHIVE.rglob('*') if p.is_file())
write(ARCHIVE / 'checksums.sha256', '\n'.join(sha(p) + '  ' + p.relative_to(ARCHIVE).as_posix() for p in archive_files) + '\n')
assert all(sha(p) == (ARCHIVE / 'checksums.sha256').read_text(encoding='utf-8').splitlines()[i][:64] for i, p in enumerate(archive_files))
git('add', '--', str(OUT.relative_to(ROOT)), 'releases/v2.1.0')
check = subprocess.run(['git', 'diff', '--cached', '--check'], cwd=ROOT, capture_output=True)
(OUT / 'staged_check.log').write_bytes(check.stdout + check.stderr)
# Historical before-snapshots and raw tool reports retain original whitespace.
# Whitespace diagnostics are recorded; they do not invalidate functional evidence.
print(f'Ready: {len(entries)} source/tool files bound; {len(archive_files)} archive files verified. No commit or push performed.')
