import argparse
import csv
import re
from pathlib import Path
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

parser = argparse.ArgumentParser()
parser.add_argument('--repo', required=True)
parser.add_argument('--output', required=True)
args = parser.parse_args()
repo = Path(args.repo)
source = repo / 'output/handoff_milestone2_20261008/source'
with (repo / 'docs/hardware/FPGA-pinplan-20261013-v0.1.csv').open(encoding='utf-8-sig', newline='') as f:
    plan = {r['signal']: r for r in csv.DictReader(f)}
cst = (source / 'constraints/primer20k_dock3714.cst').read_text(encoding='utf-8-sig')
locations = dict(re.findall(r'^IO_LOC\s+"([^"]+)"\s+(\w+);', cst, re.M))
pnr = {}
for line in (source / 'impl/pnr/instrument.rpt.txt').read_text(encoding='utf-8-sig').splitlines():
    cols = [v.strip() for v in line.split('|')]
    if len(cols) > 9 and re.fullmatch(r'gpio_key_n\[\d+\]', cols[0]):
        pnr[cols[0]] = cols
rows = []
for key in range(12):
    signal = f'gpio_key_n[{key}]'
    expected = plan[f'key{key}_n']
    actual = pnr[signal]
    pin, bank = actual[2].split('/')
    assert pin == expected['fpga_pin'] == locations[signal], (signal, pin, expected)
    assert bank == expected['bank'], (signal, bank, expected)
    assert actual[7] == 'LVCMOS33' and actual[-1] == '3.3', (signal, actual)
    rows.append([key, expected['function'], 60 + key, expected['connector'], pin, bank, actual[7], actual[-1], 'PASS'])
fig, ax = plt.subplots(figsize=(11, 6))
ax.axis('off')
table = ax.table(cellText=rows, colLabels=['Key', 'Note', 'MIDI', 'Connector', 'FPGA pin', 'Bank', 'IO type', 'PnR VCCIO', 'Match'], loc='center', cellLoc='center')
table.auto_set_font_size(False)
table.set_fontsize(11)
table.scale(1, 1.8)
for (row, col), cell in table.get_celld().items():
    cell.set_edgecolor('#cccccc')
    if row == 0:
        cell.set_facecolor('#e9edf5')
        cell.set_text_props(weight='bold')
ax.set_title('S2 GPIO pin review: pinplan = CST = Gowin PnR', fontsize=16, pad=16)
fig.text(0.5, 0.04, '2026-10-14 | 12/12 match | PnR voltage is a configured value; measure physical Bank voltage before wiring.', ha='center', fontsize=10)
fig.tight_layout(rect=(0, 0.08, 1, 1))
fig.savefig(args.output, dpi=160)
plt.close(fig)
print('PASS: all 12 GPIO pins, banks, IO types and PnR voltage settings match; PNG rendered')
