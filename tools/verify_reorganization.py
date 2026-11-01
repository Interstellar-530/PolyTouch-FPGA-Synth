"""Audit relocation bytes, historical trees, catalogs and maintained Python syntax."""
import ast
import hashlib
import json
from pathlib import Path
import re
import posixpath
from reorganize_repository import ROOT, REPORT, OLD_SOURCE, git, sha, json_write


def main():
    original=json.loads((REPORT/'original-files.json').read_text(encoding='utf-8'))
    versions=json.loads((REPORT/'versions.json').read_text(encoding='utf-8'))
    errors=[]
    unchanged=0
    immutable_count=0
    rtl_count=0
    edits=[]
    for row in original:
        p=ROOT/row['new']
        if not p.is_file():
            errors.append('Missing: '+row['new']); continue
        same=sha(p)==row['sha256']
        unchanged+=same
        if row['new'].startswith(('evidence/','releases/','experiments/','legacy/')):
            immutable_count+=1
            if not same: errors.append('Original record changed: '+row['new'])
        if row['new'].startswith('source/') and p.suffix in ('.v','.vh','.hex','.cst','.sdc'):
            rtl_count+=1
            if not same: errors.append('RTL/ROM/constraint bytes changed: '+row['new'])
        if not same: edits.append(row['new'])
    snapshots=0
    checksums=0
    for v in versions:
        base=ROOT/v['directory']
        snapshot=base/'source/original-tree'
        expected={}
        for line in git('ls-tree','-r',v['commit'],'--',OLD_SOURCE).splitlines():
            metadata,name=line.split('\t',1)
            expected[name[len(OLD_SOURCE)+1:]]=metadata.split()[2]
        actual={p.relative_to(snapshot).as_posix():p for p in snapshot.rglob('*') if p.is_file()}
        if set(actual)!=set(expected): errors.append('Snapshot inventory differs: '+v['directory'])
        for name,p in actual.items():
            b=p.read_bytes()
            blob=hashlib.sha1(b'blob '+str(len(b)).encode()+b'\0'+b).hexdigest()
            if blob!=expected.get(name): errors.append('Git blob differs: '+v['directory']+'/'+name)
            snapshots+=1
        listed=set()
        for line in (base/'catalog/checksums.sha256').read_text(encoding='utf-8').splitlines():
            digest,name=line.split('  ',1)
            p=base/name
            if not p.resolve().is_relative_to(base.resolve()) or not p.is_file() or sha(p)!=digest:
                errors.append('Catalog checksum: '+v['directory']+'/'+name)
            listed.add(name)
            checksums+=1
        all_files={p.relative_to(base).as_posix() for p in base.rglob('*') if p.is_file() and p not in (base/'catalog/checksums.sha256',base/'checksums.sha256')}
        if all_files!=listed: errors.append('Catalog inventory differs: '+v['directory'])
    python_files=set(p for p in ROOT.joinpath('source').rglob('*.py'))
    python_files.update(ROOT/r['new'] for r in original if r['new'].startswith('tools/') and r['new'].endswith('.py'))
    python_files.update(ROOT.joinpath('tools').glob('*reorganization*.py'))
    python_files.add(ROOT/'tools/reorganize_repository.py')
    for p in python_files:
        try: ast.parse(p.read_text(encoding='utf-8-sig'),filename=str(p))
        except SyntaxError as e: errors.append('Python syntax: '+str(e))
    # Detect newly broken file links in maintained original Markdown documents.
    mapping={r['old']:r['new'] for r in original}
    links=[]
    for r in original:
        if not r['new'].endswith('.md') or r['new'].startswith(('evidence/','experiments/','releases/','legacy/')): continue
        p=ROOT/r['new']
        if p.name in ('README-before-20261101.md',): continue
        for m in re.finditer(r'\[[^\]]*\]\(([^)]+)\)',p.read_text(encoding='utf-8-sig')):
            target=m[1].strip('<>').split('#',1)[0]
            if not target or target.startswith('/') or re.match(r'[a-zA-Z][\w+.-]*:',target): continue
            if not (p.parent/target).exists():
                links.append(dict(document=r['new'],target=target))
    json_write(REPORT/'link-review.json',links)
    json_write(REPORT/'preservation.json',[dict(old=r['old'],new=r['new'],original_sha256=r['sha256'],current_sha256=sha(ROOT/r['new']),unchanged=sha(ROOT/r['new'])==r['sha256']) for r in original])
    result=dict(passed=not errors,original_files=len(original),unchanged_files=unchanged,maintained_files_edited=len(edits),immutable_original_files=immutable_count,unchanged_rtl_rom_constraints=rtl_count,date_archives=len(versions),snapshot_git_blobs=snapshots,catalog_checksums=checksums,python_files_parsed=len(python_files),historical_links_for_review=len(links),errors=errors)
    json_write(REPORT/'verification.json',result)
    json_write(REPORT/'maintained-edits.json',edits)
    print(json.dumps(dict(result,errors=errors[:8],error_count=len(errors)),ensure_ascii=False,indent=2))
    raise SystemExit(0 if not errors else 1)


if __name__=='__main__': main()
