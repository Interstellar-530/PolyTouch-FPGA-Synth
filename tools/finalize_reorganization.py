"""Finish migration and regenerate catalogs. Safe to rerun; never pushes."""
from pathlib import Path
import datetime as dt
import io
import json
import zipfile
from reorganize_repository import ROOT, REPORT, ZONE, OLD_SOURCE, git, sha, write, json_write


def main():
    original=json.loads((REPORT/'original-files.json').read_text(encoding='utf-8'))
    mapping=json.loads((REPORT/'path-map.json').read_text(encoding='utf-8'))
    versions=json.loads((REPORT/'versions.json').read_text(encoding='utf-8'))
    final=next(v for v in versions if v['tag']=='final-20261030')
    for row in original:
        if row['old'].startswith('releases/FPGA-20261030-v0.1/') and '/original-delivery/' not in row['new']:
            dest=final['directory']+'/original-delivery/'+row['old'][len('releases/FPGA-20261030-v0.1/'):]
            p=ROOT/dest
            p.parent.mkdir(parents=True,exist_ok=True)
            if not p.exists(): (ROOT/row['new']).rename(p)
            row['new']=dest
            mapping[row['old']]=dest
    json_write(REPORT/'original-files.json',original)
    json_write(REPORT/'path-map.json',mapping)
    edited=json.loads((REPORT/'path-edits.json').read_text(encoding='utf-8'))
    for name in edited:
        p=ROOT/name
        data=p.read_bytes()
        for bad,good in [('docs\\\\references\\\\boards','docs/references/boards'),('docs\\references\\boards','docs/references/boards'),('docs\\\\planning\\\\电子乐器项目规划.md','docs/planning/电子乐器项目规划.md'),('docs\\planning\\电子乐器项目规划.md','docs/planning/电子乐器项目规划.md')]:
            data=data.replace(bad.encode(),good.encode())
        p.write_bytes(data)
    known={v['commit'] for v in versions}
    branches=json.loads((REPORT/'branch-inventory.json').read_text(encoding='utf-8'))
    counters={}
    for v in versions:
        counters[v['date']]=max(counters.get(v['date'],0),int(v['directory'].rsplit('.',1)[1]))
    for row in sorted(branches,key=lambda r:r['timestamp']):
        if row['commit'] in known or row['unique_commits']: continue
        date=dt.datetime.fromisoformat(row['timestamp']).astimezone(ZONE).strftime('%Y%m%d')
        counters[date]=counters.get(date,0)+1
        v=dict(tag=row['ref'],commit=row['commit'],timestamp=row['timestamp'],date=date,directory=f'releases/{date[:4]}/{date[4:6]}/FPGA-{date}-v0.{counters[date]}',kind='stage-snapshot')
        base=ROOT/v['directory']
        snapshot=base/'source/original-tree'
        packed=git('archive','--format=zip',row['commit'],OLD_SOURCE,binary=True)
        with zipfile.ZipFile(io.BytesIO(packed)) as archive:
            for name in archive.namelist():
                if not name.endswith('/'):
                    p=snapshot/name[len(OLD_SOURCE)+1:]
                    p.parent.mkdir(parents=True,exist_ok=True)
                    p.write_bytes(archive.read(name))
        write(base/'catalog/README.md',f"# {date} / 阶段快照\n\n来源 `{row['ref']}`，提交 `{row['commit']}`，时间 {row['timestamp']}。此阶段已在最终基线的历史中，按日期独立保存供查阅，不表示新增正式发布或硬件验收。\n")
        write(base/'catalog/CHANGES.md',f"# 归档变更\n\n2026-11-01：按日期保存阶段源码。原提交说明：{git('show','-s','--format=%s',row['commit'])}\n")
        write(base/'catalog/REPRODUCE.md',f"# 复现\n\n`git worktree add --detach <单独目录> {row['commit']}`，在该目录按原版 README 使用 `{OLD_SOURCE}`。本快照不改变历史工具和依赖要求。\n")
        versions.append(v)
        known.add(row['commit'])
    versions.sort(key=lambda r:(r['date'],r['timestamp'],r['tag']))
    json_write(REPORT/'versions.json',versions)
    for v in versions:
        base=ROOT/v['directory']
        has_target=any((base/'target').glob('*.fs')) or any((base/'original-delivery').rglob('*.fs'))
        write(base/'README.md',f"# {v['date']} / {v['tag']}\n\n来源、范围和校验见 [归档说明](catalog/README.md)。源码快照位于 source/original-tree；原交付包若存在则保存在 original-delivery 中。\n")
        write(base/'REPRODUCE.md','# 复现\n\n见 [复现说明](catalog/REPRODUCE.md)。历史工程按原提交的独立工作树复现。\n')
        write(base/'CHANGES.md','# 变更\n\n见 [归档变更](catalog/CHANGES.md)。2026-11-01 仅重新分类，不改写原提交历史。\n')
        write(base/'MANIFEST.md','# 清单\n\n完整文件清单见 [catalog/MANIFEST.md](catalog/MANIFEST.md)，SHA256 见 checksums.sha256。source 为原提交源码快照，target 状态见 target/README.md；原交付包位于 original-delivery（若存在）。\n')
        write(base/'target/README.md','# 目标产物\n\n'+('原位流保存在本目录或 original-delivery，来源与校验以原交付清单为准。' if has_target else '本次未收录来源可核对的目标位流，仅保留源码与记录。')+'\n')
        write(base/'evidence/README.md','# 验证依据\n\n见 [证据说明](../catalog/evidence.md)。本次保存检查不代表重新验证该历史版本。原交付包的原始证据位于 original-delivery 内（若存在）。\n')
        write(base/'catalog/target-status.md','# 目标产物\n\n'+('已保留原有位流，来源与校验以原交付清单为准。' if has_target else '本次未收录可独立核对的目标位流；仅保留源码及历史记录，不宣称构建或烧录通过。')+'\n')
        write(base/'catalog/evidence.md',f"# 证据入口\n\n本次只检查保存与分类。原提交 `{v['commit']}` 的 README、发布记录和 evidence 是历史验证依据。\n\n日期证据入口：[`evidence/2026/10`](../../../../../evidence/2026/10)。原路径见[映射说明](../../../../../docs/history/PATHS.md)。冻结交付包若存在，证据在 original-delivery 内，保持原字节。\n")
        paths=sorted(p for p in base.rglob('*') if p.is_file() and p not in (base/'catalog/checksums.sha256',base/'checksums.sha256'))
        write(base/'catalog/MANIFEST.md','# 文件清单\n\n'+''.join('- `'+p.relative_to(base).as_posix()+'`\n' for p in paths if p != base/'catalog/MANIFEST.md'))
        paths=sorted(p for p in base.rglob('*') if p.is_file() and p not in (base/'catalog/checksums.sha256',base/'checksums.sha256'))
        checks=''.join(sha(p)+'  '+p.relative_to(base).as_posix()+'\n' for p in paths)
        write(base/'catalog/checksums.sha256',checks)
        write(base/'checksums.sha256',checks)
    write(ROOT/'docs/history/VERSIONS.md','# 版本时间线\n\n按北京时间排序，同日 v0.N 是归档编号，原版本名保留。阶段快照只表示保存当时源码，不等同于正式发布。\n\n| 日期 | 原版本或阶段 | 归档 | 来源提交 |\n|---|---|---|---|\n'+''.join(f"| {v['date']} | {v['tag']} | [{Path(v['directory']).name}](../../{v['directory']}/catalog/README.md) | `{v['commit'][:12]}` |\n" for v in versions)+'\n未合并候选见 [实验目录](../../experiments/README.md)，普通提交保留在 Git 历史中。本机过程归档见 [归档清单](../../evidence/2026/11/FPGA-20261101-reorganization-v0.1/local-archives.json)。\n')
    json_write(REPORT/'preservation.json',[dict(old=r['old'],new=r['new'],original_sha256=r['sha256'],current_sha256=sha(ROOT/r['new']),unchanged=sha(ROOT/r['new'])==r['sha256']) for r in original])
    print(json.dumps(dict(versions=len(versions),originals=len(original)),indent=2))


if __name__=='__main__': main()
