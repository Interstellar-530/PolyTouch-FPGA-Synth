#!/usr/bin/env python3
"""Render one MCP3208 transaction from a VCD as a self checking review figure.

Usage:
    python tools/render_mcp3208_waveform.py <input.vcd> <output.png>
           [--transaction N] [--pad-us 1.0] [--core-clock-ns 10]

The script streams the VCD only up to the selected CS frame, then
  * checks that the frame uses 19 SCLK pulses and that DIN carries
    START, SGL/DIFF and the channel bits,
  * decodes MISO on the 8th..19th rising edge and compares the result with the
    value the DUT committed after the frame, so a frame length or bit
    alignment defect makes the run fail instead of producing a pretty picture.
Exit status is 0 when every check passes, 1 otherwise.
"""

import argparse
import sys


SCALE_TO_PS = {"s": 10**12, "ms": 10**9, "us": 10**6, "ns": 10**3, "ps": 1, "fs": 10**-3}


def parse_timescale(token):
    token = token.strip()
    for unit in ("ms", "us", "ns", "ps", "fs", "s"):
        if token.endswith(unit):
            return float(token[: -len(unit)]) * SCALE_TO_PS[unit]
    raise ValueError("unsupported timescale token %r" % token)


def parse_vcd(path, wanted, stop_after_ps):
    """Return {name: [(t_ps, value_str), ...]} for the wanted signals."""
    changes = {name: [] for name in wanted}
    code_to_name = {}
    timescale = 1.0
    in_header = True
    t = 0.0

    with open(path, "r", errors="replace") as handle:
        for raw in handle:
            line = raw.strip()
            if not line:
                continue
            if in_header:
                if line == "$enddefinitions $end":
                    in_header = False
                elif line.startswith("$timescale"):
                    token = line[len("$timescale"):].strip()
                    if not token:
                        token = handle.readline().strip()
                    if token.startswith("$end"):
                        continue
                    timescale = parse_timescale(token.split("$")[0])
                elif line.startswith("$var"):
                    parts = line.split()
                    if len(parts) >= 5 and parts[4] in wanted:
                        code_to_name[parts[3]] = parts[4]
                continue
            if line[0] == "#":
                t = float(line[1:]) * timescale
                if stop_after_ps is not None and t > stop_after_ps:
                    break
                continue
            if line[0] in "bB":
                bits, _, code = line[1:].partition(" ")
                name = code_to_name.get(code.strip())
                if name is not None:
                    changes[name].append((t, bits))
                continue
            name = code_to_name.get(line[1:].strip())
            if name is not None:
                changes[name].append((t, line[0]))
    return changes


def value_at(changes, t):
    value = "x"
    for stamp, val in changes:
        if stamp > t:
            break
        value = val
    return value


def stairs(changes, t0, t1):
    xs, ys = [t0], [value_at(changes, t0)]
    for stamp, val in changes:
        if stamp <= t0:
            ys[0] = val
            continue
        if stamp > t1:
            break
        xs.extend([stamp, stamp])
        ys.extend([ys[-1], val])
    xs.append(t1)
    ys.append(ys[-1])
    return xs, ys


def logic(value):
    return 1.0 if value == "1" else 0.0 if value == "0" else 0.5


def dout_name(index):
    if index == 7:
        return "null"
    if index >= 8:
        return "B%d" % (19 - index)
    return ""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("vcd")
    ap.add_argument("png")
    ap.add_argument("--transaction", type=int, default=1,
                    help="1 based index of the CS frame to render")
    ap.add_argument("--pad-us", type=float, default=1.0)
    ap.add_argument("--core-clock-ns", type=float, default=None)
    args = ap.parse_args()

    wanted = ["clk", "cs_n", "sclk", "mosi", "miso", "busy", "done", "data"]
    # 19 clocks at 1 MHz plus padding is far below 200 us per frame
    changes = parse_vcd(args.vcd, wanted, stop_after_ps=args.transaction * 200 * 10**6)

    cs = changes["cs_n"]
    falls = [t for i, (t, v) in enumerate(cs) if v == "0" and (i == 0 or cs[i - 1][1] != "0")]
    rises = [t for i, (t, v) in enumerate(cs) if v == "1" and i > 0 and cs[i - 1][1] == "0"]
    if len(falls) < args.transaction:
        sys.exit("only %d CS frames found in %s" % (len(falls), args.vcd))
    t_fall = falls[args.transaction - 1]
    t_rise = next(t for t in rises if t > t_fall)

    pad = args.pad_us * 10**6.0
    t0 = max(0.0, t_fall - pad)
    t1 = t_rise + pad

    sclk = changes["sclk"]
    rise_times = [t for i, (t, v) in enumerate(sclk)
                  if v == "1" and i > 0 and sclk[i - 1][1] == "0" and t_fall < t < t_rise]

    failures = []
    frame_len = len(rise_times)
    if frame_len != 19:
        failures.append("frame uses %d SCLK pulses, expected 19" % frame_len)

    din = [value_at(changes["mosi"], t - 1) for t in rise_times]
    if frame_len >= 5:
        if din[0] != "1":
            failures.append("clock 1 DIN is %s, expected the START bit 1" % din[0])
        if din[1] != "1":
            failures.append("clock 2 DIN is %s, expected SGL/DIFF = 1" % din[1])
    channel = int("".join(din[2:5]), 2) if frame_len >= 5 else -1

    decoded = "".join(value_at(changes["miso"], t - 1) for t in rise_times[7:19]) if frame_len >= 19 else ""
    committed = value_at(changes["data"], t1)
    committed_bits = committed.zfill(12)
    if decoded and set(decoded) <= set("01") and set(committed) <= set("01"):
        if committed_bits != decoded:
            failures.append("MISO on clocks 8..19 decodes to 0b%s but the DUT committed 0b%s"
                            % (decoded, committed_bits))
    else:
        failures.append("MISO on clocks 8..19 or the committed value is not clean: %r / %r"
                        % (decoded, committed))

    half_ps = (rise_times[1] - rise_times[0]) / 2.0 if frame_len > 1 else 0.0
    parts = ["frame = %d SCLK pulses" % frame_len]
    if half_ps:
        parts.append("half period %.0f ns" % (half_ps / 10**3.0))
        if args.core_clock_ns:
            parts.append("%.0f core clocks at %.0f ns" % (half_ps / 10**3.0 / args.core_clock_ns,
                                                          args.core_clock_ns))
    if channel >= 0:
        parts.append("channel %d" % channel)
    if decoded:
        parts.append("MISO b%s = 0x%03X = %d" % (decoded, int(decoded, 2), int(decoded, 2)))
    parts.append("data committed after CS rises: 0x%s" % committed_bits)
    note = ", ".join(parts)

    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    rows = [("cs_n", "cs_n"), ("sclk", "sclk"), ("mosi", "DIN (MOSI)"),
            ("miso", "DOUT (MISO)"), ("busy", "busy"), ("done", "done")]
    fig, axes = plt.subplots(len(rows), 1, sharex=True, figsize=(13.5, 8.0))
    for ax, (name, label) in zip(axes, rows):
        xs, ys = stairs(changes[name], t0, t1)
        ax.step([x / 10**6 for x in xs], [logic(y) for y in ys],
                where="post", linewidth=1.4, color="#1f4e79")
        ax.set_ylim(-0.5, 1.5)
        ax.set_yticks([0, 1])
        ax.set_yticklabels(["0", "1"], fontsize=8)
        ax.set_ylabel(label, fontsize=9, rotation=0, ha="right", va="center")
        ax.grid(True, axis="x", alpha=0.25)
        ax.tick_params(axis="x", labelsize=8)

    for index, t in enumerate(rise_times, start=1):
        axes[0].annotate(str(index), xy=(t / 10**6, 1.65), ha="center", fontsize=8, color="#c00000")
        din_label = {1: "START", 2: "SGL/DIFF", 3: "D2", 4: "D1", 5: "D0"}.get(index, "")
        if din_label:
            axes[2].annotate(din_label, xy=(t / 10**6, -1.15), ha="center", fontsize=8,
                             color="#004080", annotation_clip=False)
        if dout_name(index):
            axes[3].annotate(dout_name(index), xy=(t / 10**6, -1.15), ha="center", fontsize=8,
                             color="#800000", annotation_clip=False)

    fig.suptitle("MCP3208 mode-0 frame %d from %s (DS21298E check)"
                 % (args.transaction, args.vcd.replace("\\", "/").split("/")[-1]), fontsize=11)
    axes[-1].set_xlabel("simulation time [us]   |   " + note, fontsize=9)
    fig.tight_layout(rect=[0, 0.03, 1, 0.95])
    fig.savefig(args.png, dpi=130)
    print(note)
    print("wrote %s" % args.png)
    for item in failures:
        print("FAIL: %s" % item)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())