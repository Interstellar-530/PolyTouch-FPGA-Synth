"""Verify the compacted banks keep every retained table byte-identical and
report the worst-case change introduced by zone/band reuse."""
from pathlib import Path
import numpy as np

REPO = Path(__file__).resolve().parents[4]
AUDIO = REPO / 'output/handoff_milestone2_20261008/source/rtl/audio'
BEFORE = Path(__file__).resolve().parents[1] / 'banks_before'


def load(path, count):
    vals = [int(line.strip(), 16) for line in Path(path).read_text(encoding='ascii').splitlines() if line.strip()]
    return np.array(vals, dtype=np.uint16).view(np.int16).astype(np.float64).reshape(count, 512)


def werr(a, b):
    return 20 * np.log10(np.sqrt(np.mean((a - b) ** 2)) / np.sqrt(np.mean(a ** 2)) + 1e-12)


old_p = load(BEFORE / 'epiano_bank_all_36.hex', 36)
new_p = load(AUDIO / 'epiano_bank_all.hex', 12)
old_g = load(BEFORE / 'guitar_bank_all_36.hex', 36)
new_g = load(AUDIO / 'guitar_bank_all.hex', 30)

checks = {
    'piano group0 == old zone0': np.array_equal(new_p[0:6], old_p[0:6]),
    'piano group1 == old zone5': np.array_equal(new_p[6:12], old_p[30:36]),
    'guitar group0 == old band0': np.array_equal(new_g[0:6], old_g[0:6]),
    'guitar group1-4 == old band2-5': np.array_equal(new_g[6:30], old_g[12:36]),
    'old guitar band1 == band0': np.array_equal(old_g[6:12], old_g[0:6]),
}
for name, ok in checks.items():
    print(f'{name}: {ok}')

worst = -999.0
for z in range(1, 5):
    for s in range(6):
        worst = max(worst, werr(old_p[z * 6 + s], old_p[s]))
print(f'worst piano zone-reuse stage error: {worst:.1f} dB')
if not all(checks.values()):
    raise SystemExit('retained tables changed')
print('PASS verify_compaction')
