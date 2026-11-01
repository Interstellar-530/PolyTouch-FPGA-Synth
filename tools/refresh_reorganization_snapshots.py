"""Export Git blob bytes without Windows newline conversion; update new candidates."""
import io
import json
import zipfile
from reorganize_repository import ROOT, REPORT, OLD_SOURCE, git, sha, write


def main():
    versions=json.loads((REPORT/'versions.json').read_text(encoding='utf-8'))
    count=0
    temp=ROOT/'tmp/reorganization-20261101/snapshot-write.tmp'
    temp.parent.mkdir(parents=True,exist_ok=True)
    for v in versions:
        snapshot=ROOT/v['directory']/'source/original-tree'
        packed=git('archive','--format=zip',v['commit'],OLD_SOURCE,binary=True)
        with zipfile.ZipFile(io.BytesIO(packed)) as archive:
            for name in archive.namelist():
                if name.endswith('/'): continue
                dest=snapshot/name[len(OLD_SOURCE)+1:]
                data=archive.read(name)
                if dest.read_bytes()!=data:
                    temp.write_bytes(data)
                    temp.replace(dest)
                    count+=1
    for base in (ROOT/'experiments').rglob('source.zip'):
        provenance=json.loads((base.parent/'provenance.json').read_text(encoding='utf-8'))
        base.write_bytes(git('archive','--format=zip',provenance['commit'],OLD_SOURCE,binary=True))
        write(base.parent/'checksums.sha256',''.join(sha(p)+'  '+p.name+'\n' for p in sorted(base.parent.iterdir()) if p.is_file() and p.name!='checksums.sha256'))
    print('Normalized snapshot files:',count)


if __name__=='__main__': main()
