"""Resolve the four-bench merge while preserving the audited 12-table mapping."""
from pathlib import Path
import json, subprocess
ROOT=next(p for p in Path(__file__).resolve().parents if (p/'.git').exists())
OUT=Path(__file__).resolve().parents[1];REL=Path('output/handoff_milestone2_20261008/source');SRC=ROOT/REL
names=['tb_generic_bright.v','tb_piano_engine.v','tb_piano_envelope.v','tb_piano_morph.v']
for rev,folder in [('v2.1.0','ours'),('f7052fb','teammate')]:
    for name in names:
        dest=OUT/'before'/folder/name;dest.parent.mkdir(parents=True,exist_ok=True)
        assert not dest.exists(),'Preserve initial snapshots'
        dest.write_bytes(subprocess.check_output(['git','show',f'{rev}:{REL.as_posix()}/sim/{name}'],cwd=ROOT))
for name in names:
    text=(OUT/'before/teammate'/name).read_text(encoding='utf-8-sig')
    if name=='tb_generic_bright.v': text=text.replace('36 张钢琴表','12 张钢琴表')
    if name in ['tb_piano_engine.v','tb_piano_morph.v']:
        text=text.replace("7'd22","7'd4").replace("7'd18","7'd0").replace('bank 22','bank 4').replace('bank 18','bank 0')
    if name=='tb_piano_engine.v':
        text=text.replace('must read bank 5','must read C4 hammer bank 4')
        text=text.replace("if (piano.bank_low == 7'd4)","if (!rst && piano.state == piano.ST_LATCH_A && piano.vsel == 0 && piano.bank_low == 7'd4)")
    if name=='tb_piano_morph.v':
        text=text.replace("if (low_env.bank_low == 7'd0)","if (!rst && low_env.state == low_env.ST_LATCH_A && low_env.vsel == 0 && low_env.bank_low == 7'd0)")
        text=text.replace("if (high_env.bank_low == 7'd4)","if (!rst && high_env.state == high_env.ST_LATCH_A && high_env.vsel == 0 && high_env.bank_low == 7'd4)")
    (SRC/'sim'/name).write_text(text,encoding='utf-8',newline='\n')
result=dict(common_base='2d3db6c1700e6628341965af5bdee70d8134c526',ours='6751f6dc65c5a301af3aab8187ec3d4aaeb7d219',
    teammate='f7052fbe951e56d9839e179d14682c28ce714b05',left_only_commits=1,right_only_commits=1,
    conflict_files=['tb_piano_engine.v','tb_piano_morph.v'],retained_tables=dict(piano=12,guitar=30),production_rtl_changed=False,
    retained_ours=['all six audited optimizations','12/30 tables','bank 0/4 expectations','velocity boundary regression','32-voice prototype'],
    retained_teammate=['guitar ports tied low in piano tests','moving phase for generic comparison','120 cycles/44 products expectations','nominal velocity 127'])
(OUT/'relationship.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8',newline='\n')
print('Resolved four benches; preserved bank 0/4 and gated bank observation to active voice reads.')
