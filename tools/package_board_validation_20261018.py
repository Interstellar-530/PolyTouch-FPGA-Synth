"""Package a completed gate and the isolated board image; never program hardware."""
from pathlib import Path
import hashlib,json,re,shutil,zipfile

ROOT=Path(__file__).resolve().parents[1]
EV=ROOT/'evidence/2026/10/FPGA-板载联调-20261018-v0.1'
SRC=ROOT/'source'
WORK=ROOT/'tmp/board-only-20261018'
DEST=ROOT/'archive/FPGA-20261018-v0.2'


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    gate=(EV/'full-gate.log').read_text(encoding='utf-8-sig')
    match=re.search(r'全部\s+(\d+)\s+台正向测试台与\s+(\d+)\s+个参数负例通过，允许烧录',gate)
    assert match,'Complete gate has not passed'
    assert (EV/'full-gate-exit.txt').read_text(encoding='utf-8-sig').strip()=='0'
    assert not re.search('编译失败：|仿真失败：',gate)
    assert json.loads((EV/'board-only-compile-result.json').read_text())['exit_code']==0
    assert json.loads((EV/'board-only-simulation-result.json').read_text())['exit_code']==0
    assert (EV/'board-only-sim-passed.txt').read_text().strip()=='PASS'
    bindings=json.loads((EV/'source_binding.json').read_text())
    for rel,value in bindings.items():assert sha(ROOT/rel)==value,rel
    assert sha(EV/'board_only.fs')==(EV/'bitstream-sha256.txt').read_text().split()[0]
    capture=WORK/'final-capture'
    if capture.exists():shutil.copytree(capture,EV/'capture',dirs_exist_ok=True)
    metrics=WORK/'final-metrics'
    if metrics.exists():shutil.copytree(metrics,EV/'gate-metrics',dirs_exist_ok=True)
    timing=(EV/'reports/board_only_tr_content.html').read_text(encoding='utf-8',errors='replace')
    def endpoints(kind):
        m=re.search(r'Numbers of '+kind+r' Violated Endpoints</td>\s*<td>(\d+)</td>',timing)
        assert m;return int(m[1])
    assert endpoints('Setup')==0 and endpoints('Hold')==0
    user_code=re.search(rb'^//UserCode:\s*(0x[0-9A-Fa-f]+)',(EV/'board_only.fs').read_bytes(),re.M)
    assert user_code
    summary={'positive_benches':int(match[1]),'parameter_negative_cases':int(match[2]),
             'gate_exit':0,'board_only_sim_exit':0,'setup_violations':0,'hold_violations':0,
             'clock_hz':27000000,'sample_rate_hz':46875,'estimated_fmax_mhz':59.260,
             'logic':4533,'registers':1770,'bsram':4,'mult18x18':1,'board_ports':14,
             'bitstream_sha256':sha(EV/'board_only.fs'),
             'expected_user_code':user_code[1].decode('ascii'),
             'capture_test_sha256':sha(SRC/'sim/tb_audio_capture.v')}
    (EV/'validation-summary.json').write_text(json.dumps(summary,indent=2),encoding='utf-8')
    live=json.loads((EV/'live-results.json').read_text(encoding='utf-8-sig'))
    live['full_gate']='PASS';(EV/'live-results.json').write_text(json.dumps(live,ensure_ascii=False,indent=2),encoding='utf-8')
    DEST.mkdir(parents=True,exist_ok=True)
    marker=DEST/'BOARD_ONLY_VALIDATION.txt'
    if marker.exists():assert marker.read_text().strip()=='board_only_20261018_v0.1'
    else:
        assert not list(DEST.iterdir()),'Nonempty unrelated archive'
        marker.write_text('board_only_20261018_v0.1\n',encoding='ascii')
    for folder in ['source','deliverables','evidence']:(DEST/folder).mkdir(exist_ok=True)
    for name in ['board_only_validation_20261018.py','package_board_validation_20261018.py',
                 'load_board_only_20261018.ps1','test_board_timbre_20261018.ps1','analyze_audio_capture.py']:
        shutil.copy2(ROOT/'tools'/name,DEST/'source'/name)
    shutil.copy2(ROOT/'docs/hardware/FPGA-无外设板载验证-20261018-v0.1.md',DEST/'deliverables')
    shutil.copy2(EV/'board_only.fs',DEST/'deliverables')
    shutil.copytree(EV,DEST/'evidence',dirs_exist_ok=True)
    with zipfile.ZipFile(DEST/'source/production-and-tests.zip','w',zipfile.ZIP_DEFLATED) as archive:
        for folder in ['rtl','sim','constraints']:
            for path in sorted((SRC/folder).rglob('*')):
                if path.is_file() and path.suffix.lower() in {'.v','.vh','.hex','.cst','.sdc','.ps1','.py','.txt','.md'}:
                    archive.write(path,path.relative_to(ROOT).as_posix())
        for path in sorted((SRC/'build').iterdir()):
            if path.is_file() and path.suffix.lower() in {'.ps1','.tcl','.tsv','.list','.md'}:
                archive.write(path,path.relative_to(ROOT).as_posix())
        for path in sorted((SRC/'build/isolated').glob('*.v')):
            archive.write(path,path.relative_to(ROOT).as_posix())
    (DEST/'REPRODUCE.md').write_text('''# 复现与使用边界

原工作区为 E:/Working Space/FPGA。运行时 C:/iverilog、E:/Gowin、tools/.venv-docconvert、tools/.venv-audio-analysis 是保留依赖，不随临时目录清理。
source/production-and-tests.zip 保留本次生产 RTL、完整门禁及测试输入；evidence/source 是独立裸板封装与约束。
在干净工作区复现时，先把 production-and-tests.zip 解压到工作区根目录，再将 source 下五个 .py/.ps1 脚本复制到工作区 tools/，从工作区根目录运行下列命令。

```powershell
& 'tools/.venv-docconvert/Scripts/python.exe' 'tools/board_only_validation_20261018.py' sim
& 'tools/.venv-docconvert/Scripts/python.exe' 'tools/board_only_validation_20261018.py' build
& './source/sim/run_simulation.ps1' -AudioCaptureDir 'E:/Working Space/FPGA/tmp/board-only-20261018/final-capture' -MetricsDir 'E:/Working Space/FPGA/tmp/board-only-20261018/final-metrics' -BuildDir 'E:/Working Space/FPGA/tmp/board-only-20261018/final-sim-build'
& 'tools/.venv-audio-analysis/Scripts/python.exe' 'tools/analyze_audio_capture.py' --capture 'tmp/board-only-20261018/final-capture/audio_capture.csv' --manifest 'tmp/board-only-20261018/final-capture/capture_manifest.csv' --output-dir 'evidence/2026/10/FPGA-板载联调-20261018-v0.1/digital-audio-analysis'
```

完整门禁、专用自检和 SHA256 必须全部通过才可加载目标位流。这里只用于板载27MHz/PT8211/USB/耳机，外设排针空置；不验证外部 ADC、FSR、键盘、DAC。
本归档不自动烧录，不改 Flash。是否已加载及实际音色反馈以 evidence/live-results.json 为准。
门禁及归档核验后，经用户确认可执行 tools/load_board_only_20261018.ps1 临时加载 SRAM；随后 tools/test_board_timbre_20261018.ps1 播放三段同音高、不同音色的五秒持续音，并在结束时静音。
''',encoding='utf-8')
    (DEST/'CHANGELOG.md').write_text('''# 变更

新增独立 board_only_top，固定外接按键释放，并用现有 ADC_CENTER 参数实现无外设时的中性弯音；生产音频 RTL 未改。
修正旧 tb_audio_capture 静音稳定等待8帧为140帧，对应已存在的128帧VCA淡出；保留58880帧捕获和原有断言。
旧0x5633固件的串口、单音、和弦逐音释放、静音恢复已有用户现场反馈；其T0返回ERR。
新固件的仿真、布局布线与实机结果分开记录；没有借此宣称模拟质量或外设验收完成。
沙箱Icarus失败、中文路径Gowin失败日志保留；后续使用沙箱外工具与ASCII临时路径。
代码回退仅涉及本轮测试台改动和新增测试文件；Flash不改，临时SRAM配置可断电退出。
''',encoding='utf-8')
    files=sorted(p for p in DEST.rglob('*') if p.is_file() and p.name not in {'MANIFEST.md','checksums.sha256'})
    manifest=['# MANIFEST','',f'完整门禁：{match[1]}台正向、{match[2]}个参数负例通过。',
              '实机加载状态及听感以 evidence/live-results.json 为准。','',
              '| 文件 | 字节 |','|---|---|']
    manifest += [f'| {p.relative_to(DEST).as_posix()} | {p.stat().st_size} |' for p in files]
    (DEST/'MANIFEST.md').write_text('\n'.join(manifest)+'\n',encoding='utf-8')
    files=sorted(p for p in DEST.rglob('*') if p.is_file() and p.name!='checksums.sha256')
    records=[(sha(p),p.relative_to(DEST).as_posix()) for p in files]
    (DEST/'checksums.sha256').write_text('\n'.join(h+'  '+n for h,n in records)+'\n',encoding='utf-8')
    assert all(sha(DEST/n)==h for h,n in records)
    print(json.dumps({'files_hashed':len(records),'gate_benches':int(match[1]),'gate_negative_cases':int(match[2])}))


if __name__=='__main__':main()
