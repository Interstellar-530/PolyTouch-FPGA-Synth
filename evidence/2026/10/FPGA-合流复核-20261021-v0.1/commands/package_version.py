"""Create a new, self-contained local candidate archive; never overwrite one."""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import subprocess

ROOT = next(p for p in Path(__file__).resolve().parents if (p / '.git').exists())
EVIDENCE = Path(__file__).resolve().parents[1]
PREFIX = 'output/handoff_milestone2_20261008/source/'


def git(*args):
    return subprocess.check_output(['git', '-c', 'core.quotepath=false', *args], cwd=ROOT)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--archive', type=Path, default=ROOT / 'archive/FPGA-20261021-v0.1')
    args = parser.parse_args()
    target = args.archive.resolve()
    if target.exists():
        raise RuntimeError(f'archive already exists: {target}')
    if ROOT.resolve() not in target.parents:
        raise RuntimeError('archive must stay within this workspace')
    target.mkdir(parents=True)
    for name in git('ls-files', '-z', PREFIX).decode('utf-8').split('\0'):
        if not name:
            continue
        dst = target / 'source' / name[len(PREFIX):]
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / name, dst)
    for name in ['gen_piano_prom.py', 'gen_bright_prom.py', 'gen_epiano_bank.py']:
        (target / 'tools').mkdir(exist_ok=True)
        shutil.copy2(ROOT / 'tools' / name, target / 'tools' / name)
    shutil.copytree(EVIDENCE, target / 'evidence')
    (target / 'reports').mkdir()
    for name in ['README.md', 'docs/releases/v2.0.0.md', 'docs/releases/v2.0.1.md',
                 'docs/reviews/FPGA-Git差异与优化方向-20261021-v0.1.md']:
        shutil.copy2(ROOT / name, target / 'reports' / Path(name).name)
    metrics = json.loads((EVIDENCE / 'build_metrics.json').read_text(encoding='utf-8'))
    (target / 'target').mkdir()
    shutil.copy2(Path(metrics['bitstream']), target / 'target/debug8usb.fs')
    patch = git('diff', '--binary', '2d3db6c', '--', 'README.md', 'docs/releases/v2.0.0.md',
                PREFIX + 'sim/run_simulation.ps1')
    (target / 'reports/tracked_changes.patch').write_bytes(patch)
    (target / 'baseline').mkdir()
    for name in ['README.md', 'docs/releases/v2.0.0.md', PREFIX + 'sim/run_simulation.ps1']:
        dst = target / 'baseline' / name
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_bytes(git('show', '2d3db6c:' + name))
    (target / 'CHANGELOG.md').write_text(
        '# v2.0.1 本地候选版\n\n基线 2d3db6c；远端 main 与基线一致，既有 USB/音频合流保留。'
        '本次只修验证门禁和说明；生产 RTL/约束未改变。门禁缺失测试即退出 1，新增五台已有产品回归注册。'
        '定向测试和 debug8usb PnR 有本轮证据；完整门禁按用户要求中止，没有烧录或推送。\n', encoding='utf-8')
    (target / 'REPRODUCE.md').write_text(
        '# 复现与回退\n\n归档目录为当前工作目录。先核验 checksums.sha256；编译工具需另装 Gowin V1.9.11.03 Education、Icarus Verilog 与 Python 3。'
        '工具环境没有复制进归档，普通构建使用已保存的 HEX/ROM，不需下载样本。\n\n'
        '```powershell\n'
        "& '.\\source\\build\\build.ps1' -Profile debug8usb -GwSh 'E:\\Gowin\\Gowin_V1.9.11.03_Education_x64\\IDE\\bin\\gw_sh.exe'\n"
        "& '<Python 3 路径>' -B '.\\evidence\\commands\\verify_integration.py'\n"
        '```\n\n短验证在归档中优先选择 ./source，生成文件写工作区 tmp；不得把它当作完整烧录门禁。'
        '本次位流为 target/debug8usb.fs，PT8211、27MHz、8 声部、CH9350L+FSR；未烧录。'
        'standard27 是 PCM5102A，本轮只展开，若要使用应另行构建和验证。\n\n'
        '在原工作区可用 `git apply -R --check <归档>/reports/tracked_changes.patch` 检查后反向应用，恢复三个已跟踪文件；'
        '新增版本说明/报告/证据是独立文件，按明确路径处理，不用 reset --hard 或 clean。'
        'baseline/ 也保存了这三个文件的原始字节。不要覆盖用户原有未跟踪位流、PDF 和报告。\n', encoding='utf-8')
    (target / 'MANIFEST.md').write_text(
        '# FPGA-20261021-v0.1\n\n项目：PolyTouch FPGA Synth；候选软件版本 v2.0.1；基线 '+git('rev-parse','2d3db6c').decode().strip()+'.\n\n'
        '| 路径 | 内容 |\n|---|---|\n| source/ | 唯一生产源码的当前快照，含构建入口、约束与测试 |\n'
        '| tools/ | ROM 重建及原始波表再制作脚本，后者仍需源 WAV/numpy |\n'
        '| target/debug8usb.fs | 本轮 PT8211 调试位流；未烧录 |\n'
        '| evidence/ | 比较、定向检查、原始中止记录、资源/时序及命令 |\n'
        '| reports/ | 发布说明、8 项优化报告与跟踪文件补丁 |\n'
        '| baseline/ | 三个跟踪文件的 2d3db6c 原始内容 |\n'
        '| REPRODUCE.md / CHANGELOG.md | 复现、回退和变更边界 |\n\n'
        'SHA256 覆盖本目录除 checksums.sha256 自身以外的全部文件。完整门禁没有通过结论，standard27 没有本轮 PnR/位流，硬件听感和延迟未测。'
        '用户原文件和既有依赖保留，清理结果见 evidence/cleanup.json。\n', encoding='utf-8')
    rows = []
    for path in sorted(target.rglob('*')):
        if path.is_file() and path.name != 'checksums.sha256':
            rows.append(hashlib.sha256(path.read_bytes()).hexdigest() + '  ' + path.relative_to(target).as_posix())
    (target / 'checksums.sha256').write_text('\n'.join(rows) + '\n', encoding='utf-8')
    print(json.dumps(dict(archive=str(target), files=len(rows), bitstream_sha256=metrics['bitstream_sha256']), ensure_ascii=False))


if __name__ == '__main__':
    main()
