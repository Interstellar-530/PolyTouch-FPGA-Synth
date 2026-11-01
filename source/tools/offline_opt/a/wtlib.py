"""A-line offline wavetable utilities.

Single-cycle tables are DEPTH=512 signed 16-bit samples stored one per line as
four ASCII hex digits (two's complement), which is what the checked-in
``*.hex`` files and ``tools/gen_gowin_prom_init.py`` already use.

Nothing here touches the RTL; the module is imported by the measurement,
generator and vector scripts under ``tools/offline_opt/a``.
"""
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

import numpy as np

DEPTH = 512
WORD_BITS = 16
HARD_MAX_HARMONIC = DEPTH // 2 - 1          # 255: h*2 < DEPTH
NYQUIST_MARGIN = 0.45                       # design margin from the plan
FS_HZ = 48000.0


# ----------------------------------------------------------------- hex io ---
def read_hex(path: Path) -> np.ndarray:
    """Read one 512-sample table as int16 values."""
    words = [w.strip() for w in Path(path).read_text(encoding="ascii").split() if w.strip()]
    if len(words) != DEPTH:
        raise ValueError(f"{path}: expected {DEPTH} words, found {len(words)}")
    raw = np.array([int(w, 16) for w in words], dtype=np.int32)
    if raw.min() < 0 or raw.max() > 0xFFFF:
        raise ValueError(f"{path}: word outside 16 bits")
    return (raw - (raw >= 0x8000) * 0x10000).astype(np.int64)


def read_bank_hex(path: Path, tables: int) -> np.ndarray:
    words = [w.strip() for w in Path(path).read_text(encoding="ascii").split() if w.strip()]
    if len(words) != tables * DEPTH:
        raise ValueError(f"{path}: expected {tables * DEPTH} words, found {len(words)}")
    raw = np.array([int(w, 16) for w in words], dtype=np.int64)
    signed = raw - (raw >= 0x8000) * 0x10000
    return signed.reshape(tables, DEPTH)


def format_hex_table(table: np.ndarray) -> str:
    return "".join(f"{int(v) & 0xFFFF:04X}\n" for v in table)


def write_hex(path: Path, tables: np.ndarray) -> None:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    flat = np.asarray(tables, dtype=np.int64).reshape(-1)
    path.write_text(format_hex_table(flat), encoding="ascii")


def sha256(path: Path) -> str:
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


# ------------------------------------------------------------- spectrum ----
def spectrum(table: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Return (amplitude, phase) for harmonics 0..DEPTH/2.

    amplitude[h] is the peak amplitude of cos(2*pi*h*n/DEPTH + phase[h]), so a
    full-scale sine gives amplitude[1] == 32767.
    """
    x = np.asarray(table, dtype=np.float64)
    spec = np.fft.rfft(x) / DEPTH
    amp = np.abs(spec) * 2.0
    amp[0] = abs(spec[0])
    phase = np.angle(spec)
    return amp, phase


def resynthesise(amp: np.ndarray, phase: np.ndarray, h_max: int) -> np.ndarray:
    """Round a band-limited harmonic set back to DEPTH int16 samples."""
    spec = np.zeros(DEPTH // 2 + 1, dtype=np.complex128)
    hi = min(h_max, DEPTH // 2)
    spec[1:hi + 1] = (amp[1:hi + 1] / 2.0) * np.exp(1j * phase[1:hi + 1])
    spec[0] = amp[0]
    x = np.fft.irfft(spec * DEPTH, n=DEPTH)
    return np.clip(np.rint(x), -32768, 32767).astype(np.int64)


# -------------------------------------------------------------- metrics ----
def rms_dbfs(table: np.ndarray) -> float:
    rms = float(np.sqrt(np.mean(np.asarray(table, dtype=np.float64) ** 2)))
    return 20.0 * np.log10(max(rms, 1e-12) / 32768.0)


def peak_dbfs(table: np.ndarray) -> float:
    peak = float(np.max(np.abs(np.asarray(table, dtype=np.float64))))
    return 20.0 * np.log10(max(peak, 1e-12) / 32768.0)


def dc_lsb(table: np.ndarray) -> float:
    return float(np.mean(np.asarray(table, dtype=np.float64)))


def max_adjacent_step(table: np.ndarray) -> int:
    """Largest |x[n+1]-x[n]| including the last-to-first wrap pair."""
    x = np.asarray(table, dtype=np.int64)
    d = np.abs(np.diff(np.concatenate([x, x[:1]])))
    return int(d.max())


def significant_harmonics(amp: np.ndarray, floor_db: float = -60.0) -> int:
    """Highest harmonic whose amplitude is within ``floor_db`` of the peak."""
    peak = float(amp[1:].max()) if amp.size > 1 else 0.0
    if peak <= 0:
        return 0
    ref = peak * 10.0 ** (floor_db / 20.0)
    idx = np.nonzero(amp[1:] >= ref)[0]
    return int(idx.max()) + 1 if idx.size else 0


def bandlimit_harmonic(f_max_hz: float, fs_hz: float = FS_HZ,
                       margin: float = NYQUIST_MARGIN) -> int:
    """Conservative harmonic cap from the plan: min(255, floor(margin*fs/f_max))."""
    if f_max_hz <= 0:
        raise ValueError("f_max_hz must be positive")
    return int(min(HARD_MAX_HARMONIC, np.floor(margin * fs_hz / f_max_hz)))


def alias_residual(table: np.ndarray, f0_hz: float, fs_hz: float = FS_HZ,
                   floor_dbfs: float = -90.0) -> dict:
    """Model the aliasing a 512-point single-cycle table produces at ``f0_hz``.

    Every harmonic h is placed at h*f0; components above Nyquist fold to
    |h*f0 - fs*round(h*f0/fs)|, which is not a harmonic of f0 for the pitches
    this project plays, so the folded energy is in-band noise.  The returned
    residual is aliased power over in-band signal power (negative dB is good).

    ``floor_dbfs`` ignores harmonic bins quieter than that, so the number
    describes folded *content* and not the 16-bit quantisation floor of the
    table (one LSB is -96 dBFS).  The model delibereately excludes
    interpolation and phase-accumulator quantisation: it measures the table's
    band limit, not the whole datapath.
    """
    amp, _ = spectrum(table)
    amp = amp.copy()
    amp[0] = 0.0                                   # DC carries no pitch
    amp[amp * 2.0 / 65536.0 < 10.0 ** (floor_dbfs / 20.0)] = 0.0
    h = np.arange(amp.size)
    f = h * f0_hz
    in_band = f <= fs_hz / 2.0
    sig = float(np.sum((amp[in_band] ** 2) / 2.0))
    aliased_mask = ~in_band
    aliased_mask[0] = False
    if not np.any(aliased_mask):
        return {"f0_hz": f0_hz, "h_nyquist": int(np.floor(fs_hz / 2.0 / f0_hz)),
                "signal_rms": float(np.sqrt(sig)), "aliased_rms": 0.0,
                "alias_db": -199.0, "worst_alias_hz": 0.0}
    fold = np.abs(f[aliased_mask] - fs_hz * np.round(f[aliased_mask] / fs_hz))
    aliased_rms = float(np.sqrt(np.sum((amp[aliased_mask] ** 2) / 2.0)))
    worst = float(fold[np.argmax(amp[aliased_mask])])
    if sig <= 0 or aliased_rms <= 0:
        alias_db = -199.0
    else:
        alias_db = 20.0 * np.log10(aliased_rms / np.sqrt(sig))
    return {"f0_hz": f0_hz, "h_nyquist": int(np.floor(fs_hz / 2.0 / f0_hz)),
            "signal_rms": float(np.sqrt(sig)), "aliased_rms": aliased_rms,
            "alias_db": float(alias_db), "worst_alias_hz": worst}


def phase_alignment_shift(reference: np.ndarray, table: np.ndarray) -> int:
    """Circular shift of ``table`` that maximises correlation with ``reference``.

    A circular shift only rotates harmonic phases, so it can align the morph
    chain without changing any table's magnitude spectrum.
    """
    a = np.asarray(reference, dtype=np.float64)
    b = np.asarray(table, dtype=np.float64)
    corr = np.fft.irfft(np.fft.rfft(a) * np.conj(np.fft.rfft(b)), n=DEPTH)
    return int(np.argmax(corr))


def circular_shift(table: np.ndarray, shift: int) -> np.ndarray:
    return np.roll(np.asarray(table, dtype=np.int64), -int(shift))


def morph_step(table_a: np.ndarray, table_b: np.ndarray, weight: float) -> dict:
    """Pointwise step when the mix moves from ``table_a`` to a blend.

    Models one stage transition: the engine output is
    lerp(T[bank], T[bank+1], w/65536), so a transition that changes bank and
    weight at once steps by the difference of the two blends.  Returns the
    peak/RMS step and the same statistics for the steady-state waveform slope,
    so a transition is only called a click when it exceeds normal motion.
    """
    blended = table_a.astype(np.int64) + np.rint(
        weight * (table_b.astype(np.int64) - table_a.astype(np.int64))).astype(np.int64)
    step = blended - table_a.astype(np.int64)
    slope = np.diff(np.concatenate([table_a[-1:], table_a])).astype(np.int64)
    return {
        "weight": float(weight),
        "step_peak_lsb": int(np.max(np.abs(step))),
        "step_rms_lsb": float(np.sqrt(np.mean(step.astype(np.float64) ** 2))),
        "source_slope_peak_lsb": int(np.max(np.abs(slope))),
        "source_slope_rms_lsb": float(np.sqrt(np.mean(slope.astype(np.float64) ** 2))),
    }


# --------------------------------------------------------------- pROM init --
def prom_init_words(pair: list[np.ndarray]) -> list[int]:
    """64 x 256-bit INIT_RAM words for two 512-point tables (AD[13:4] = word)."""
    samples = np.concatenate([np.asarray(t, dtype=np.int64).reshape(-1) for t in pair])
    if samples.size != 1024:
        raise ValueError("a pROM pair holds exactly two 512-point tables")
    words = []
    for w in range(64):
        value = 0
        for k in range(16):
            value |= (int(samples[w * 16 + k]) & 0xFFFF) << (16 * k)
        words.append(value)
    return words


def emit_prom_params(words: list[int], indent: str = " ") -> str:
    lines = []
    for i, value in enumerate(words):
        comma = "," if i < len(words) - 1 else ""
        lines.append(f"{indent}.INIT_RAM_{i:02X}(256'h{value:064X}){comma}")
    return "\n".join(lines)


_INIT_RE = re.compile(r"\.INIT_RAM_([0-9A-F]{2})\(256'h([0-9A-Fa-f]{64})\)")
_PROM_RE = re.compile(r"\)\s+(gp\d+|u_bank\d+)\s*\(\s*\.DO\((\w+)\)")


def parse_prom_module(path: Path) -> dict:
    """Decode a generated bank wrapper back into its 512-point tables.

    The wrapper is the ROM initialisation that actually ships, so decoding it
    (instead of re-reading the hex) is what proves "hex, vendor init and
    metadata delivered together".  Returns ``{prom_index: [table_a, table_b]}``
    with each table a list of 512 signed samples.
    """
    text = Path(path).read_text(encoding="ascii")
    current = None
    words: list[int] = []
    tables: dict[int, list[list[int]]] = {}
    for line in text.splitlines():
        if re.match(r"\s*pROM\s*#\(", line):
            current = len(tables)
            words = [None] * 64
            tables[current] = []
            continue
        match = _INIT_RE.search(line)
        if match:
            if current is None:
                raise ValueError(f"{path}: INIT_RAM outside a pROM instance")
            words[int(match.group(1), 16)] = int(match.group(2), 16)
            continue
        if current is not None and ".DO(" in line:
            if any(w is None for w in words):
                raise ValueError(f"{path}: pROM instance {current} has < 64 INIT words")
            samples = []
            for w in words:
                for k in range(16):
                    value = (w >> (16 * k)) & 0xFFFF
                    samples.append(value - 0x10000 if value & 0x8000 else value)
            tables[current] = [samples[:DEPTH], samples[DEPTH:]]
            current = None
    if not tables:
        raise ValueError(f"{path}: no pROM instances found")
    return tables


def json_dump(path: Path, payload) -> None:
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Path(path).write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n",
                          encoding="utf-8")


# ------------------------------------------------------------- note tables --
def midi_hz(note: float) -> float:
    return 440.0 * 2.0 ** ((note - 69.0) / 12.0)
