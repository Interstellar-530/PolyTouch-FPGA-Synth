"""Measure the audition difference in absolute dBFS and per-segment terms."""
from pathlib import Path
import wave
import numpy as np

AUD = Path(__file__).resolve().parents[1] / 'audio' / 'piano'


def read_wav(path):
    with wave.open(str(path), 'rb') as w:
        assert w.getnchannels() == 1 and w.getsampwidth() == 2
        fs = w.getframerate()
        x = np.frombuffer(w.readframes(w.getnframes()), dtype='<i2').astype(np.float64) / 32768.0
    return x, fs


before, fs = read_wav(AUD / 'before.wav')
after, _ = read_wav(AUD / 'after.wav')
diff, _ = read_wav(AUD / 'diff.wav')

n = min(len(before), len(after))
b, a = before[:n], after[:n]
d = a - b

print(f'sample rate      : {fs}')
print(f'before RMS       : {20*np.log10(np.sqrt(np.mean(b**2))):8.2f} dBFS   peak {20*np.log10(np.max(np.abs(b))):7.2f} dBFS')
print(f'diff RMS         : {20*np.log10(np.sqrt(np.mean(d**2))):8.2f} dBFS   peak {20*np.log10(np.max(np.abs(d))):7.2f} dBFS')
print(f'diff / signal RMS: {20*np.log10(np.sqrt(np.mean(d**2))/np.sqrt(np.mean(b**2))):8.2f} dB')
print(f'16-bit LSB       : {-20*np.log10(32768):8.2f} dBFS  (1 LSB = 1/32768)')
print(f'diff peak in LSB : {np.max(np.abs(d))*32768:8.2f}')
print(f'diff RMS in LSB  : {np.sqrt(np.mean(d**2))*32768:8.3f}')

# correlation with the signal: a gain error would be strongly correlated
corr = np.corrcoef(b, d)[0, 1]
print(f'corr(signal,diff): {corr:8.3f}')

# per 0.7 s note segment (six notes, 50 ms gap each)
seg = int(0.7 * fs)
gap = int(0.05 * fs)
pos = 0
for i in range(6):
    s = slice(pos, pos + seg)
    rms = 20 * np.log10(np.sqrt(np.mean(d[s] ** 2)) + 1e-20)
    print(f'note {i}: diff RMS {rms:8.2f} dBFS  signal {20*np.log10(np.sqrt(np.mean(b[s]**2))+1e-20):7.2f} dBFS')
    pos += seg + gap

spec = np.abs(np.fft.rfft(d)) ** 2
freq = np.fft.rfftfreq(len(d), 1 / fs)
band = [(0, 200), (200, 1000), (1000, 5000), (5000, 15000), (15000, fs / 2)]
tot = spec[1:].sum()
print('diff energy by band:')
for lo, hi in band:
    m = (freq >= lo) & (freq < hi)
    print(f'  {lo:5.0f}-{hi:5.0f} Hz: {10*np.log10(spec[m].sum()/tot + 1e-20):7.1f} dB of total')
