"""Verify documentation links and binding to existing RTL/CST; does not simulate hardware."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
sys.stdout.reconfigure(encoding='utf-8')
documents = [
    'README.md',
    'docs/hardware/FPGA-硬件搭建指导-20261022-v0.1.md',
    'docs/hardware/FPGA-硬件搭建指导-20261022-v0.2.md',
    'docs/hardware/FPGA-硬件采买与搭建准备-20261022-v0.1.md',
    'docs/hardware/FPGA-硬件采买与搭建准备-20261022-v0.2.md',
    'docs/hardware/FPGA-周末硬件组装清单与安装说明-20261020-v0.1.md',
    'docs/reviews/FPGA-硬件搭建交叉核查-20261022-v0.1.md',
]
checks = []
def check(name, passed, detail=''):
    checks.append({'check': name, 'passed': bool(passed), 'detail': detail})

for name in documents:
    file = ROOT / name
    check('document_exists', file.is_file(), name)
    if not file.is_file():
        continue
    content = file.read_text(encoding='utf-8-sig')
    for link in re.findall(r'\[[^\]]*\]\(([^)]+)\)', content):
        if re.match(r'^[a-zA-Z][a-zA-Z0-9+.-]*:', link) or link.startswith('#'):
            continue
        target = link.split('#')[0]
        check('relative_link_exists', (file.parent / target).exists(), name + ' -> ' + link)
    check('no_replacement_character', '\ufffd' not in content, name)

prefix = 'output/handoff_milestone2_20261008/source/'
cst_name = prefix + 'constraints/primer20k_i2s_27m.cst'
cst = (ROOT / cst_name).read_text(encoding='utf-8-sig')
pins = dict(re.findall(r'IO_LOC\s+"([^"]+)"\s+(\w+)\s*;', cst))
expected = {'clk_27m': 'H11', 'kbd_uart_rx': 'L9', 'kbd_uart_tx': 'N8',
            'adc_cs_n': 'N6', 'adc_sck': 'D11', 'adc_mosi': 'A11', 'adc_miso': 'B11',
            'i2s_bck': 'B12', 'i2s_lrck': 'C12', 'i2s_din': 'B13', 'dac_xsmt': 'P6'}
for port, pin in expected.items():
    check('standard27_cst_mapping', pins.get(port) == pin, f'{port}={pin}')
check('standard27_has_no_T7_clock', 'clk_12m288' not in pins and 'T7' not in pins.values())
wrapper_name = prefix + 'build/isolated/top_std27_build.v'
wrapper = (ROOT / wrapper_name).read_text(encoding='utf-8-sig')
for param, value in [('VOICES', 8), ('GPIO_KEY_ENABLE', 0), ('HOST_KBD_ENABLE', 1), ('AUDIO_IF', 2)]:
    check('standard27_parameter', bool(re.search(r'\.' + param + r'\(\s*' + str(value) + r'\s*\)', wrapper)), f'{param}={value}')
host_name = prefix + 'rtl/audio/host_kbd_input.v'
host = (ROOT / host_name).read_text(encoding='utf-8-sig')
check('watchdog_merge_still_pending', 'parameter integer TIMEOUT_POLICY' not in host,
      'Current reviewed integration code still uses original timeout policy.')
guide = (ROOT / documents[2]).read_text(encoding='utf-8')
for fragment in ['RXD 接模块 GND', 'N8 不连接该节点', '尚未', '完整仿真门禁', '46.875kHz', 'DC-036A-2.5A-2.0']:
    check('guide_required_clarification', fragment in guide, fragment)
for p in ['build/build.ps1', 'build/program_sram.ps1', 'sim/run_simulation.ps1']:
    check('command_target_exists', (ROOT / prefix / p).is_file(), p)
bindings = documents + [cst_name, wrapper_name, host_name]
hashes = {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in bindings}
head = subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'], text=True).strip()
source_commit = subprocess.check_output(['git', '-C', str(ROOT), 'log', '-1', '--format=%H', '--', prefix], text=True).strip()
result = {'result': 'PASS' if all(c['passed'] for c in checks) else 'FAIL',
          'verification_base_commit': head, 'source_last_commit': source_commit,
          'scope': 'Document/source consistency only; no simulation, PnR, physical measurement or programming.',
          'checks': checks, 'sha256': hashes}
(HERE / 'verification.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'result': result['result'], 'checks': len(checks), 'failures': [c for c in checks if not c['passed']]}, ensure_ascii=False))
sys.exit(0 if result['result'] == 'PASS' else 1)
