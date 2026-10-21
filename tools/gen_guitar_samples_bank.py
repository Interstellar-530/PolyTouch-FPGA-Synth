"""Build 36 real electric-guitar tables from Karoryfer Black And Green (CC0).

v2: estimate f0, decompose the steady segment into exact harmonics (Goertzel),
gate non-harmonic noise, apply a gentle 6.5 kHz rolloff, and synthesize a
strictly periodic 512-point table. This removes the low-note loop click that
time-domain period extraction produced.
"""
from pathlib import Path
import argparse
import json
import re
import numpy as np
import soundfile as sf

REPO = Path(__file__).resolve().parents[1]
DEFAULT_AUDIO = REPO / 'output/handoff_milestone2_20261008/source/rtl/audio'
DEFAULT_SAMPLES = REPO / 'tmp/karoryfer/black-and-green-guitars-main/Samples'
FS = 46875

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--repo-root', type=Path, default=REPO,
                    help='repository root used to resolve the default paths')
parser.add_argument('--samples', type=Path,
                    help='Karoryfer Black And Green "Samples" directory '
                         '(default: <repo-root>/tmp/karoryfer/black-and-green-guitars-main/Samples)')
parser.add_argument('--out-dir', type=Path,
                    help='generated output directory (default: <repo-root>/output/.../rtl/audio)')
args = parser.parse_args()
ROOT = args.repo_root.resolve()
AUDIO = (args.out_dir or ROOT / 'output/handoff_milestone2_20261008/source/rtl/audio').resolve()
SAMPLES = (args.samples or ROOT / 'tmp/karoryfer/black-and-green-guitars-main/Samples').resolve()
if not SAMPLES.is_dir():
    raise SystemExit(f'sample directory not found: {SAMPLES} (pass --samples or --repo-root)')
AUDIO.mkdir(parents=True, exist_ok=True)

EDGES = [40, 48, 56, 64, 72, 80, 89]
CENTERS = [(EDGES[i] + EDGES[i + 1] - 1) // 2 for i in range(6)]
# Keyboard band 0 and 1 resolve to the same source sample (identical tables), so
# they share one table group. Five groups x six variants = 30 tables.
GROUPS = [[0, 1], [2], [3], [4], [5]]
VARIANTS = [('green', 'p'), ('green', 'mf'), ('green', 'f'),
            ('black', 'p'), ('black', 'mf'), ('black', 'f')]
NOTE_BASE = {'c': 0, 'd': 2, 'e': 4, 'f': 5, 'g': 7, 'a': 9, 'b': 11}
PAT = re.compile(r'twang_([a-g])(b|#)?(-?\d+)_(p|mf|f)_rr1\.flac$')


def note_midi(name):
    m = PAT.match(name)
    if not m:
        return None
    letter, accidental, octave, dyn = m.groups()
    midi = 12 * (int(octave) + 1) + NOTE_BASE[letter]
    if accidental == 'b':
        midi -= 1
    elif accidental == '#':
        midi += 1
    return midi


def midi_f(n):
    return 440.0 * 2.0 ** ((n - 69) / 12.0)


def estimate_f0(seg, sr, expected):
    """Zero-padded FFT peak + parabolic interpolation around the expected f0."""
    n = len(seg)
    w = seg * np.hanning(n)
    nfft = 1 << 17
    S = np.abs(np.fft.rfft(w, nfft))
    freqs = np.fft.rfftfreq(nfft, 1.0 / sr)
    lo = np.searchsorted(freqs, expected * 0.94)
    hi = np.searchsorted(freqs, expected * 1.06)
    k = lo + int(np.argmax(S[lo:hi]))
    if 0 < k < len(S) - 1:
        a, b, c = S[k - 1], S[k], S[k + 1]
        denom = (a - 2 * b + c)
        delta = 0.5 * (a - c) / denom if abs(denom) > 1e-20 else 0.0
        delta = max(-1.0, min(1.0, delta))
    else:
        delta = 0.0
    return (k + delta) * sr / nfft


def harmonic_table(seg, sr, f0, fmax):
    """Exact harmonic decomposition at f0; suppress noise; synthesize 512 points."""
    n = np.arange(len(seg))
    win = np.hanning(len(seg))
    segw = (seg - seg.mean()) * win
    hmax = min(180, max(1, int(0.45 * FS / f0)))
    amps, phases, freqs = [], [], []
    zero_run = 0
    for h in range(1, hmax + 1):
        fh = h * f0
        if fh > 0.47 * sr:
            break
        # Goertzel-style direct DFT at the exact harmonic frequency.
        A = 2.0 / len(seg) * np.sum(segw * np.exp(-2j * np.pi * fh * n / sr))
        a = abs(A)
        amps.append(a)
        phases.append(np.angle(A))
        freqs.append(fh)
        if h > 1:
            rel = a / max(amps[0], 1e-12)
            if rel < 0.0008:
                zero_run += 1
                if zero_run >= 4:
                    break
            else:
                zero_run = 0
    amps = np.asarray(amps)
    phases = np.asarray(phases)
    freqs = np.asarray(freqs)
    # remove the 4 trailing gated harmonics
    keep = len(amps) - min(zero_run, max(0, len(amps) - 1))
    amps, phases, freqs = amps[:keep], phases[:keep], freqs[:keep]
    # gentle cabinet-ish rolloff above 6.5 kHz
    lp = 1.0 / (1.0 + (freqs / 6500.0) ** 2)
    amps = amps * lp
    idx = np.arange(512)
    w = np.zeros(512)
    for a, ph, h in zip(amps, phases, range(1, len(amps) + 1)):
        w += a * np.cos(2 * np.pi * h * idx / 512.0 + ph)
    w = w - w.mean()
    return w, len(amps), freqs[-1] if len(freqs) else 0.0


tables = []
meta = []
for group, bands in enumerate(GROUPS):
    band = bands[0]
    target = CENTERS[band]
    fmax_band = midi_f(EDGES[band + 1] - 1)
    for vi, (guitar, dyn) in enumerate(VARIANTS):
        folder = SAMPLES / guitar / 'ord'
        cands = []
        for p in folder.glob(f'twang_*_{dyn}_rr1.flac'):
            nm = note_midi(p.name)
            if nm is not None:
                cands.append((abs(nm - target), nm, p))
        if not cands:
            raise RuntimeError(f'no sample {guitar}/{dyn}')
        cands.sort()
        _, note, path = cands[0]
        d, sr = sf.read(str(path), always_2d=True)
        d = d.mean(axis=1).astype(float)
        start = min(int(0.08 * sr), max(0, len(d) - 8192))
        seg = d[start:start + 8192]
        expected = midi_f(note)
        f0 = estimate_f0(seg, sr, expected)
        w, nh, fhi = harmonic_table(seg, sr, f0, fmax_band)
        peak = max(np.max(np.abs(w)), 1e-9)
        w = np.rint(w * 32767.0 / peak).astype(int)
        tables.append(w)
        (AUDIO / f'wave_guitar_g{group}v{vi}.hex').write_text(
            ''.join(f'{int(v) & 0xFFFF:04X}\n' for v in w), encoding='ascii')
        seam = abs(w[0] - w[-1])
        meta.append({'group': group, 'bands': bands, 'variant': vi, 'guitar': guitar,
                     'dynamic': dyn, 'source_note': note, 'file': path.name,
                     'f0_est': round(float(f0), 2), 'harmonics_used': nh,
                     'highest_hz': round(float(fhi), 1), 'seam': int(seam)})
        print(f'g{group} (bands {bands}) v{vi} {guitar}/{dyn} {path.name} f0={f0:.1f} '
              f'h={nh} hi={fhi:.0f} seam={seam}')

(AUDIO / 'guitar_bank_all.hex').write_text(
    ''.join(f'{int(v) & 0xFFFF:04X}\n' for t in tables for v in t), encoding='ascii')

lines = [
    '// Generated by tools/gen_guitar_samples_bank.py v2 (Karoryfer CC0).',
    '// 30 tables = 5 band groups x 6 variants, exact-f0 harmonics, 15 BSRAM.',
    'module gowin_prom_guitar_bank(input wire clk,ce,rst, input wire [5:0] bank,',
    ' input wire [8:0] addr, output reg [15:0] dout);',
    'reg [3:0] selected=0;',
    'always @(posedge clk) if(rst) selected<=0; else if(ce) selected<=bank[4:1];',
]
for g in range(15):
    lines.append(f'wire [31:0] gd{g};')
lines += ['always @* case(selected)']
for g in range(15):
    lines.append(f" 4'd{g}: dout=gd{g}[15:0];")
lines += [' default: dout=16\'d0;', 'endcase']
for g in range(15):
    pair = np.concatenate([tables[g * 2], tables[g * 2 + 1]])
    lines.append("pROM #(.READ_MODE(1'b0),.BIT_WIDTH(6'd16),.RESET_MODE(\"SYNC\"),")
    for w in range(64):
        value = sum((int(v) & 0xFFFF) << (16 * k)
                    for k, v in enumerate(pair[w * 16:w * 16 + 16]))
        lines.append(f' .INIT_RAM_{w:02X}(256\'h{value:064X})' + (',' if w < 63 else ''))
    lines += [f' ) gg{g} (.DO(gd{g}),.AD({{bank[0],addr,4\'b0}}),',
              f' .CLK(clk),.CE(ce && bank[4:1]==4\'d{g}),.OCE(1\'b1),.RESET(rst));']
lines += ['endmodule', '']
(AUDIO / 'gowin_prom_guitar_bank.v').write_text('\n'.join(lines), encoding='ascii')
(AUDIO / 'guitar_bank_meta.json').write_text(
    json.dumps({'source': 'Karoryfer Black And Green Guitars', 'license': 'CC0',
                'method': 'exact-f0 harmonic decomposition + 6.5 kHz rolloff',
                'tables': 30, 'depth': 512, 'bsram_blocks': 15,
                'bands': EDGES, 'variants': [f'{g}/{d}' for g, d in VARIANTS],
                'groups': GROUPS, 'entries': meta}, indent=2) + '\n', encoding='utf-8')
print('done', len(tables))
