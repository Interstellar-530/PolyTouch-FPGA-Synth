"""Rebuild maintained text path edits from the byte-preserved original backup."""
import json
import posixpath
import re
import zipfile
from pathlib import Path
from reorganize_repository import ROOT, REPORT, AUDIT, OLD_SOURCE, apply_replacements, json_write


def main():
    original=json.loads((REPORT/'original-files.json').read_text(encoding='utf-8'))
    mapping={r['old']:r['new'] for r in original}
    replacements={OLD_SOURCE:'source','docs/minimum_design':'docs/design/minimum_design','board_docs':'docs/references/boards','output/pdf':'docs/exports/pdf','docs/releases':'docs/history/release-notes','docs/research':'docs/references/research','output/handoff_milestone2_20261008/reference':'docs/references/handoff-20261008','output/handoff_milestone2_20261008':'docs/history/handoff-20261008','电子乐器项目规划.md':'docs/planning/电子乐器项目规划.md'}
    replacements.update({old:new for old,new in mapping.items() if old!=new and not old.startswith(('rtl/','sim/','constraints/','build/'))})
    for old,new in mapping.items():
        if old.startswith('docs/evidence/'):
            group=old.split('/')[2]
            replacements['docs/evidence/'+group]=new.split(group)[0]+group
    for old,new in [('releases/v1.0.0','releases/2026/10/FPGA-20261013-v0.1/target'),('releases/v2.1.0','releases/2026/10/FPGA-20261021-v0.2/original-delivery'),('releases/FPGA-20261030-v0.1','releases/2026/10/FPGA-20261030-v0.1/original-delivery')]:
        replacements[old]=new
    edits=[]
    with zipfile.ZipFile(AUDIT/'before-files.zip') as backup:
        for row in original:
            old,new=row['old'],row['new']
            p=ROOT/new
            if new.startswith(('evidence/','releases/','experiments/','archive/','legacy/')): continue
            if p.suffix.lower() not in ('.md','.txt','.py','.ps1','.tcl','.json','.code-workspace'): continue
            if new.startswith('docs/history/') and p.suffix.lower() in ('.json','.txt'): continue
            raw=backup.read(old)
            try: text=raw.decode('utf-8-sig')
            except UnicodeDecodeError: continue
            links=[]
            def link(m):
                label,target=m.group(1),m.group(2)
                if re.match(r'[a-zA-Z][\w+.-]*:',target) or target.startswith(('#','/')): return m[0]
                base,sep,fragment=target.strip('<>').partition('#')
                resolved=posixpath.normpath(posixpath.join(posixpath.dirname(old),base))
                mapped=mapping.get(resolved)
                if mapped:
                    result='['+label+']('+posixpath.relpath(mapped,posixpath.dirname(new) or '.')+(sep+fragment if sep else '')+')'
                else: result=m[0]
                links.append(result)
                return 'REORGANIZE_LINK_'+str(len(links)-1)+'_END'
            updated=re.sub(r'\[([^\]]*)\]\(([^)]+)\)',link,text) if p.suffix.lower()=='.md' else text
            updated=apply_replacements(updated,replacements)
            for i,value in enumerate(links): updated=updated.replace('REORGANIZE_LINK_'+str(i)+'_END',value)
            updated=updated.replace(' / "output" / "handoff_milestone2_20261008" / "source"',' / "source"')
            if new=='source/sim/run_simulation.ps1':
                updated=updated.replace("'..\\..\\..\\tmp'","'..\\tmp'").replace("$sourceRoot '..\\..\\..'","$sourceRoot '..'")
            encoded=updated.encode('utf-8')
            if raw.startswith(b'\xef\xbb\xbf') or (p.suffix.lower()=='.ps1' and any(ord(c)>127 for c in updated)):
                encoded=b'\xef\xbb\xbf'+encoded
            if p.read_bytes()!=encoded:
                temp=ROOT/'tmp/reorganization-20261101/path-rewrite.tmp'
                temp.parent.mkdir(parents=True,exist_ok=True)
                temp.write_bytes(encoded)
                temp.replace(p)
            if encoded!=raw: edits.append(new)
    json_write(REPORT/'path-edits.json',edits)
    print('Rebuilt path edits:',len(edits))


if __name__=='__main__': main()
