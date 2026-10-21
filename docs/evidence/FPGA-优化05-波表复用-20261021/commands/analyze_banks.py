"""Reproduce the item-5 analysis: harmonic content, zone/band redundancy,
stage-merge cost and 256-point depth cost for the checked-in banks.

Read-only. Run with the project venv (numpy is required).
"""
from pathlib import Path
import numpy as np

REPO = Path(__file__).resolve().parents[4]
AUDIO = REPO / 'output/handoff_milestone2_20261008/source/rtl/audio'


def load(path, count):
    vals = [int(line.strip(), 16) for line in path.read_text(encoding='ascii').splitlines() if line.strip()]
    return np.array(vals, dtype=np.uint16).view(np.int16).astype(np.float64).reshape(count, 512)


def werr(a, b):
    return 20 * np.log10(np.sqrt(np.mean((a - b) ** 2)) / np.sqrt(np.mean(a ** 2)) + 1e-12)


def harm_count(table, floor_db=-60.0):
    spec = np.abs(np.fft.rfft(table))
    idx = np.nonzero(spec >= spec[1:].max() * 10 ** (floor_db / 20))[0]
    return int(idx.max()) if len(idx) else 0


def depth_err(table, factor=2):
    half = table[::factor]
    x = np.arange(len(table)) / factor
    i0 = np.floor(x).astype(int) % len(half)
    i1 = (i0 + 1) % len(half)
    frac = x - np.floor(x)
    return werr(table, half[i0] * (1 - frac) + half[i1] * frac)


def alias_frac(table, keep=128):
    spec = np.abs(np.fft.rfft(table)) ** 2
    return float(spec[keep:].sum() / spec[1:].sum())


piano = load(AUDIO / 'epiano_bank_all.hex', 12)
guitar = load(AUDIO / 'guitar_bank_all.hex', 30)
old_p = load(REPO / 'docs/evidence/FPGA-优化05-波表复用-20261021/banks_before/epiano_bank_all_36.hex', 36)
old_g = load(REPO / 'docs/evidence/FPGA-优化05-波表复用-20261021/banks_before/guitar_bank_all_36.hex', 36)

print('== harmonic count (new banks, -60 dB) ==')
print('piano:', [harm_count(t) for t in piano])
print('guitar:', [harm_count(t) for t in guitar])

print('\n== piano: old zone vs zone0 (dB, per stage max/mean) ==')
for z in range(1, 6):
    errs = [werr(old_p[s], old_p[z * 6 + s]) for s in range(6)]
    print(f'  zone{z}: max {max(errs):6.1f}  mean {np.mean(errs):6.1f}')

print('\n== piano: stage merge cost (old layout, mean over zones) ==')
for s in range(5):
    print(f'  s{s}->s{s+1}: {np.mean([werr(old_p[z*6+s], old_p[z*6+s+1]) for z in range(6)]):6.1f} dB')

print('\n== guitar: band0 vs band1 identity ==')
print('  bit-identical:', np.array_equal(old_g[0:6], old_g[6:12]))

print('\n== 256-point depth cost (new banks) ==')
print('  piano err dB:', [round(depth_err(t), 1) for t in piano])
print('  guitar err dB:', [round(depth_err(t), 1) for t in guitar])
print('  piano alias energy above h128, max dB:',
      round(max(10 * np.log10(alias_frac(t) + 1e-20) for t in piano), 1))

print('\n== bright bank: h16 vs plain ==')
b16 = load(AUDIO / 'wave_bright_h16.hex', 1)[0]
plain = load(AUDIO / 'wave_bright.hex', 1)[0]
print('  bit-identical:', np.array_equal(b16, plain))
