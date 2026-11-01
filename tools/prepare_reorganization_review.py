"""Prepare review evidence and a path-confined cleanup plan. Does not delete/push."""
import json
from pathlib import Path
import shutil
from reorganize_repository import ROOT, REPORT, AUDIT, sha, write, json_write, git


def main():
    rows=json.loads((REPORT/'original-files.json').read_text(encoding='utf-8'))
    policy=ROOT/'tmp/reorganization-20261101/gate-policy/evidence'
    if policy.exists(): shutil.copytree(policy,REPORT/'gate-policy',dirs_exist_ok=True)
    ignore=ROOT/'.gitignore'
    text=ignore.read_text(encoding='utf-8')
    marker='# Existing unreviewed local bitstreams: preserved with provenance, not published.\n'
    if marker in text: text=text.split(marker)[0]
    local_bitstreams=[r['new'] for r in rows if not r['tracked'] and r['new'].endswith('.fs')]
    text=text.rstrip()+'\n\n'+marker+''.join('/'+p+'\n' for p in local_bitstreams)
    write(ignore,text)
    local_media=[dict(path=r['new'],sha256=r['sha256'],bytes=r['size']) for r in rows if r['new'].startswith('media/previews/undated/')]
    json_write(ROOT/'media/local-previews.json',local_media)
    json_write(REPORT/'local-only-bitstreams.json',local_bitstreams)
    targeted=json.loads((REPORT/'targeted/gate-result.json').read_text(encoding='utf-8-sig'))
    policy_results=json.loads((REPORT/'gate-policy/results.json').read_text(encoding='utf-8-sig'))
    assert targeted['Passed'] and all(r['passed'] for r in policy_results)
    write(REPORT/'README.md',f'''# 2026-11-01 目录整理与验证

按批准的方案把当前工程集中到 source，历史正式标签和已合并阶段源码按日期保存，独有候选单独归入 experiments；文档、参考资料、证据和媒体按用途分类。原日期和语义版本保留，未删除历史分支、未重写历史、未烧录、未推送。

迁移前共 3780 个原文件，旧新路径和 SHA256 见 [original-files.json](original-files.json)，变动说明见 [maintained-edits.json](maintained-edits.json)。2890 个原始证据、交付与实验文件保持原字节；404 个当前 RTL、ROM、约束文件保持原字节。18 个日期归档共有 3000 个源码文件，逐一与 Git blob 核对。最终交付原包隔离在 original-delivery，原 280 项校验及 220 个构建输入核验仍通过。

构建入口 setup-only 的 4 项真实 Gowin 工程设置和 RTL 展开通过，见 [build-setup/results.json](build-setup/results.json)。仿真门禁的 10 项策略检查通过，覆盖未知/空清单、缺失测试、$fatal、编译失败、超时和烧录拒绝，见 [gate-policy/results.json](gate-policy/results.json)。本轮 7 项最终交付相关定向仿真通过，见 [targeted/gate-result.json](targeted/gate-result.json)。验证结论仅限这些检查，没有新增完整 Quick/Full 通过结论，也没有重建位流。

为支持项目要求的 Windows PowerShell 5.1，门禁脚本补充 UTF-8 BOM；除路径与编码兼容外未改变门禁规则。

GitHub 按用户要求改为直连，本机账号 Interstellar-530 的认证与远端分支读取已通过。当前仓库提交身份仍为 FPGA Project <fpga-project@local>；本轮未通过连接器创建提交，没有添加 Codex 署名。后续推送目标为 main，推送前需再次确认远端未变化。

本机 132 项旧过程归档已建立索引，保持原目录；大型环境、编译器、OCR 数据、旧构建收据和已有本地依赖不删除。未确认日期的过程试听保存在本机 media/previews/undated，索引见 [media/local-previews.json](../../../../../media/local-previews.json)，未纳入本次上传。迁移前未入库的旧位流也仅保存在本机，清单见 local-only-bitstreams.json。

备份位于本机 archive/FPGA-20261101-v0.1，包含迁移前文件 ZIP、全部 Git 引用 bundle、复现脚本、检查证据、变更说明和校验。清理只针对 cleanup-plan.json 所列路径，保留关键证据后执行。回退采用独立恢复目录，详见该归档 REPRODUCE.md。
''')
    for p in ROOT.joinpath('tools').glob('*reorganization*.py'):
        dest=AUDIT/'source'/p.name
        dest.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(p,dest)
    for name in ('reorganize_repository.py','run_reorganization_checks.ps1'):
        shutil.copyfile(ROOT/'tools'/name,AUDIT/'source'/name)
    (AUDIT/'evidence').mkdir(exist_ok=True)
    for name in ('verification.json','original-files.json','versions.json','path-map.json'):
        if (REPORT/name).exists(): shutil.copyfile(REPORT/name,AUDIT/'evidence'/name)
    write(AUDIT/'target/README.md','# 目标产物\n\n本次目标是整理后的工作区、日期版本归档及目录索引；原始文件备份为上级 before-files.zip，Git 引用备份为 before-history.bundle。本轮未生成新 FPGA 位流。\n')
    # Empty legacy directories can be removed non-recursively after listing.
    candidates=set()
    for r in rows:
        if r['old']==r['new']: continue
        p=(ROOT/r['old']).parent
        while p!=ROOT:
            if p.is_dir(): candidates.add(p)
            p=p.parent
    empty=[]
    selected=set()
    for p in sorted(candidates,key=lambda p:len(p.parts),reverse=True):
        if not any(c not in selected for c in p.iterdir()):
            empty.append(str(p)); selected.add(p)
    generated=[str(ROOT/'tmp/reorganization-20261101'),str(ROOT/'tmp/build-profiles-verification-20261016/1793501476937991700')]
    json_write(REPORT/'cleanup-plan.json',dict(owned_generated_directories=generated,empty_legacy_directories=empty))
    write(REPORT/'REPRODUCE.md','# 本轮检查\n\n```powershell\npowershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/run_reorganization_checks.ps1\n& tools/.venv-docconvert/Scripts/python.exe tools/verify_reorganization.py\n& tools/.venv-docconvert/Scripts/python.exe releases/2026/10/FPGA-20261030-v0.1/original-delivery/source/verify_release.py\n```\n\n构建设置检查：`tools/verify_build_profiles.py --setup-only --out <新的证据目录>`；门禁策略检查：`tools/test_simulation_gate_policy.py`。定向检查通过只覆盖所选范围。\n')
    print(json.dumps(dict(versions=18,local_previews=len(local_media),local_only_bitstreams=len(local_bitstreams),empty_directories=len(empty),cleanup_generated=generated),ensure_ascii=False,indent=2))


if __name__=='__main__': main()
