"""Build listening controls for the audition: a digital-silence null, and a
real timbre change boosted by the same +40 dB as diff.wav.

Run with the project venv from the repository root:
    python commands/make_controls.py
"""
from pathlib import Path
import sys
import wave
import numpy as np

HERE = Path(__file__).resolve().parents[1]
REPO = HERE.parents[2]
sys.path.insert(0, str(REPO / 'tools'))
import render_bank_ab as rb  # noqa: E402

AUDIO = REPO / 'output/handoff_milestone2_20261008/source/rtl/audio'
OUT = HERE / 'audio' / 'piano'
FS = 46875
FS_OUT = 48000
NOTES = [36, 48, 60, 67, 72, 84]
SECONDS = 0.7
GAP = int(0.05 * FS)
BOOST = 10 ** (40 / 20.0)


def phrase(bank, tone):
    parts = []
    for note in NOTES:
        parts.append(rb.render_note(bank, 'piano', note, 100, SECONDS, FS, tone, 'after'))
        parts.append(np.zeros(GAP))
    return np.concatenate(parts)


def write(path, x, peak):
    rb.write_wav(path, x, FS_OUT, peak)


bank = rb.read_bank(AUDIO / 'epiano_bank_all.hex', 12)
soft = phrase(bank, 0)       # start_stage 3
hard = phrase(bank, 3)       # start_stage 4 (brighter attack)
n = min(len(soft), len(hard))
soft, hard = soft[:n], hard[:n]
diff = hard - soft
level = 20 * np.log10(np.sqrt(np.mean(diff ** 2)) / np.sqrt(np.mean(soft ** 2)) + 1e-20)
print(f'stage-change diff / signal: {level:6.1f} dB')

peak = max(np.max(np.abs(soft)), np.max(np.abs(hard)), 1e-9)
write(OUT / 'diff_control_stage.wav', rb.resample(diff * BOOST, FS, FS_OUT), peak)
write(OUT / 'null_control.wav', np.zeros(FS_OUT), 1.0)
(OUT / 'controls.txt').write_text(
    'null_control.wav      : digital silence (player/room noise reference)\n'
    f'diff_control_stage.wav: real attack-timbre change, diff/signal {level:.1f} dB, +40 dB boost\n'
    'diff.wav              : compaction residual, diff/signal -77.6 dB, +40 dB boost\n',
    encoding='utf-8')
print('wrote controls')
