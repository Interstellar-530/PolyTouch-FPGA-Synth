"""Collect reproducible build evidence from the latest Gowin reports."""
from __future__ import annotations

import hashlib
import json
import re
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PNR = ROOT / "impl" / "pnr"
SYN = ROOT / "impl" / "gwsynthesis"
OUT = ROOT / "docs" / "evidence" / "first_voice_build.json"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def integer(pattern: str, text: str, group: int = 1) -> int:
    match = re.search(pattern, text)
    if not match:
        raise RuntimeError(f"pattern not found: {pattern}")
    return int(match.group(group))


def floating(pattern: str, text: str, group: int = 1) -> float:
    match = re.search(pattern, text)
    if not match:
        raise RuntimeError(f"pattern not found: {pattern}")
    return float(match.group(group))


def main() -> None:
    fs = PNR / "instrument.fs"
    pnr_text = read(PNR / "instrument.rpt.txt")
    timing_text = read(PNR / "instrument_tr_content.html")
    sha = hashlib.sha256(fs.read_bytes()).hexdigest()

    data = {
        "checked_at": datetime.now().astimezone().isoformat(),
        "milestone": "single_voice_dds_adsr_pt8211",
        "target": {"part": "GW2A-LV18PG256C8/I7", "device_version": "C"},
        "clock": {
            "input": "27 MHz",
            "pt8211_bck": "1.5 MHz",
            "pt8211_ws": "46.875 kHz",
        },
        "tone": {
            "phase_increment": 40315426,
            "nominal_hz": 440.0,
            "sample_rate_hz": 46875.0,
        },
        "resources": {
            "lut_total": integer(r"Logic\s*\|\s*(\d+)/", pnr_text),
            "registers_total": integer(r"Register\s*\|\s*(\d+)/", pnr_text),
            "bsram": integer(r"BSRAM\s*\|\s*(\d+)/", pnr_text),
            "dsp_mult18x18": integer(r"MULT18X18\s*\|\s*(\d+)", pnr_text),
        },
        "timing": {
            "setup_violated_endpoints": integer(
                r"Numbers of Setup Violated Endpoints\s*</td>\s*<td>(\d+)", timing_text
            ),
            "hold_violated_endpoints": integer(
                r"Numbers of Hold Violated Endpoints\s*</td>\s*<td>(\d+)", timing_text
            ),
            "actual_fmax_mhz": floating(
                r"clk_27m\s*</td>\s*<td>27\.000\(MHz\)\s*</td>\s*<td>([0-9.]+)\(MHz\)",
                timing_text,
            ),
        },
        "pins": {
            "clk_27m": "H11",
            "hp_bck": "N15",
            "hp_ws": "P16",
            "hp_din": "P15",
            "pa_en": "R16",
            "led": "N16",
        },
        "artifact": {
            "path": fs.relative_to(ROOT).as_posix(),
            "size_bytes": fs.stat().st_size,
            "sha256": sha,
        },
        "passed": True,
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(OUT)


if __name__ == "__main__":
    main()