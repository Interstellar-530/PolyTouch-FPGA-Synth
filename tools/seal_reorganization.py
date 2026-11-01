"""Verify staged bytes, then seal review and rollback archive checksums."""
import hashlib
import json
from pathlib import Path
import shutil
import zipfile
from reorganize_repository import ROOT, REPORT, AUDIT, OLD_SOURCE, BASELINE, git, sha, write, json_write


def blob(path):
    data=path.read_bytes()
    return hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()


def main():
    staged={}
    for line in git('ls-files','--stage').splitlines():
        meta,name=line.split('\t',1)
        staged[name]=meta.split()[1]
    before={}
    for line in git('ls-tree','-r',BASELINE,'--',OLD_SOURCE).splitlines():
        meta,name=line.split('\t',1)
        before[name]=meta.split()[2]
    original=json.loads((REPORT/'original-files.json').read_text(encoding='utf-8'))
    errors=[]
    production=0
    frozen=0
    for r in original:
        name=r['new']
        if name.startswith('source/') and Path(name).suffix in ('.v','.vh','.hex','.cst','.sdc'):
            production+=1
            if staged.get(name)!=before.get(r['old']): errors.append('Staged RTL differs: '+name)
    for name,expected in staged.items():
        p=ROOT/name
        if p.stat().st_size>=100*1024*1024: errors.append('Oversized Git blob: '+name)
        if name.startswith(('releases/2026/','evidence/','experiments/')):
            frozen+=1
            if blob(p)!=expected: errors.append('Staged byte preservation mismatch: '+name)
    json_write(REPORT/'index-verification.json',dict(passed=not errors,staged_files=len(staged),production_files_equal_original_git_blobs=production,frozen_files_equal_worktree_bytes=frozen,errors=errors))
    if errors: raise RuntimeError(str(errors[:8]))
    local=json.loads((REPORT/'local-archives.json').read_text(encoding='utf-8'))
    for row in local:
        if row['directory']=='archive/PolyTouch-FPGA-Synth-20261027-v0.3':
            row['moved_to']='experiments/2026/10/FPGA-20261027-hid-review-v0.1'
    json_write(REPORT/'local-archives.json',local)
    readme=(REPORT/'README.md').read_text(encoding='utf-8')
    readme=readme.replace('本机 132 项旧过程归档已建立索引，保持原目录','本机旧过程归档已建立索引，迁入实验目录的条目通过映射追溯')
    write(REPORT/'README.md',readme)
    files=sorted(p for p in REPORT.rglob('*') if p.is_file() and p.name!='checksums.sha256')
    write(REPORT/'MANIFEST.md','# 整理交付清单\n\n源文件位于仓库 source/，日期归档位于 releases/2026/10/，重现入口见 REPRODUCE.md。\n\n'+''.join('- `'+p.relative_to(REPORT).as_posix()+'`\n' for p in files if p.name!='MANIFEST.md'))
    files=sorted(p for p in REPORT.rglob('*') if p.is_file() and p.name!='checksums.sha256')
    write(REPORT/'checksums.sha256',''.join(sha(p)+'  '+p.relative_to(REPORT).as_posix()+'\n' for p in files))
    # Archive contains final scripts and evidence in addition to the original backup.
    for p in ROOT.joinpath('tools').glob('*reorganization*.py'):
        shutil.copyfile(p,AUDIT/'source'/p.name)
    shutil.copyfile(ROOT/'tools/reorganize_repository.py',AUDIT/'source/reorganize_repository.py')
    shutil.copyfile(ROOT/'tools/run_reorganization_checks.ps1',AUDIT/'source/run_reorganization_checks.ps1')
    shutil.copytree(REPORT,AUDIT/'evidence/review',dirs_exist_ok=True)
    with zipfile.ZipFile(AUDIT/'before-files.zip') as backup:
        assert backup.testzip() is None, 'Backup ZIP CRC failure'
    paths=sorted(p for p in AUDIT.rglob('*') if p.is_file() and p.name!='checksums.sha256')
    write(AUDIT/'MANIFEST.md','# FPGA-20261101-v0.1\n\n源文件与可复现脚本在 source/；整理结果见 target/README.md；原始文件和 Git 备份分别为 before-files.zip、before-history.bundle；验证证据在 evidence/review；变更与回退见 CHANGES.md、REPRODUCE.md。\n\n'+''.join('- `'+p.relative_to(AUDIT).as_posix()+'`\n' for p in paths if p.name!='MANIFEST.md'))
    paths=sorted(p for p in AUDIT.rglob('*') if p.is_file() and p.name!='checksums.sha256')
    write(AUDIT/'checksums.sha256',''.join(sha(p)+'  '+p.relative_to(AUDIT).as_posix()+'\n' for p in paths))
    print(json.dumps(dict(staged_files=len(staged),production_git_blobs_verified=production,frozen_staged_bytes_verified=frozen,report_files=len(files),backup_zip_crc='PASS'),indent=2))


if __name__=='__main__': main()
