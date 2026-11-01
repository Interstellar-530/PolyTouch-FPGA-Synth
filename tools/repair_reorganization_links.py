"""Repair relocated Markdown links to files historically addressed from repo root."""
import json
import os
import re
from reorganize_repository import ROOT, REPORT, json_write


def main():
    original=json.loads((REPORT/'original-files.json').read_text(encoding='utf-8'))
    mapping={r['old']:r['new'] for r in original}
    repairs=[]
    temp=ROOT/'tmp/reorganization-20261101/link-rewrite.tmp'
    for r in original:
        if not r['new'].endswith('.md') or r['new'].startswith(('evidence/','experiments/','releases/','legacy/')): continue
        p=ROOT/r['new']
        raw=p.read_bytes()
        text=raw.decode('utf-8-sig')
        def fix(m):
            label,target=m[1],m[2]
            base,sep,fragment=target.strip('<>').partition('#')
            if not base or base.startswith('/') or re.match(r'[a-zA-Z][\w+.-]*:',base) or (p.parent/base).exists(): return m[0]
            if base.startswith('docs/references/') and '/' not in base[len('docs/references/'):]:
                candidate=ROOT/'docs/references/boards/Tang_Primer_20K_Dock_3714'/base.split('/')[-1]
            else: candidate=ROOT/mapping.get(base,base)
            if not candidate.is_file(): return m[0]
            relative=os.path.relpath(candidate,p.parent).replace('\\','/')
            repairs.append(dict(document=r['new'],old=target,new=relative))
            return '['+label+']('+relative+(sep+fragment if sep else '')+')'
        updated=re.sub(r'\[([^\]]*)\]\(([^)]+)\)',fix,text)
        if updated!=text:
            data=updated.encode('utf-8')
            if raw.startswith(b'\xef\xbb\xbf'): data=b'\xef\xbb\xbf'+data
            temp.parent.mkdir(parents=True,exist_ok=True)
            temp.write_bytes(data)
            temp.replace(p)
    json_write(REPORT/'link-repairs.json',repairs)
    print('Links repaired:',len(repairs))


if __name__=='__main__': main()
