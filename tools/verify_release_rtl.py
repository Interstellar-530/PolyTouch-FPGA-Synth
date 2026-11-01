"""Compare comment-insensitive RTL tokens and exact assets with a Git baseline.

This lexical check is paired with the project's complete RTL simulation gate.
It does not build a bitstream, probe hardware, or substitute for simulation.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SOURCE = "source/"
TOKEN = re.compile(
    r"(?:\d+)?'[sS]?[bBoOdDhH][0-9a-fA-F_xXzZ?]+|"
    r"'(?:0|1|x|z)|\d+(?:\.\d+)?(?:[eE][+-]?\d+)?|"
    r"[a-zA-Z_$][a-zA-Z0-9_$]*|"
    r"<<<|>>>|===|!==|<<|>>|<=|>=|==|!=|&&|\|\||\*\*|\+\+|--|"
    r"~\^|\^~|~&|~\||::|\+:|-:|=>|\*>|."
)


def rtl_tokens(source):
    result = []
    cursor = 0
    while cursor < len(source):
        if source[cursor].isspace():
            cursor += 1
        elif source.startswith("//", cursor):
            cursor = source.find("\n", cursor)
            if cursor < 0:
                break
        elif source.startswith("/*", cursor):
            end = source.find("*/", cursor + 2)
            if end < 0:
                raise ValueError("Unclosed Verilog comment")
            cursor = end + 2
        elif source[cursor] == '"':
            start = cursor
            cursor += 1
            while cursor < len(source):
                if source[cursor] == "\\":
                    cursor += 2
                elif source[cursor] == '"':
                    cursor += 1
                    result.append(source[start:cursor])
                    break
                else:
                    cursor += 1
            else:
                raise ValueError("Unclosed Verilog string")
        elif source[cursor] == "\\":
            start = cursor
            while cursor < len(source) and not source[cursor].isspace():
                cursor += 1
            result.append(source[start:cursor])
        else:
            match = TOKEN.match(source, cursor)
            if not match:
                raise ValueError("Unknown token at " + str(cursor))
            result.append(match[0])
            cursor = match.end()
    return result


def git_bytes(baseline, path):
    return subprocess.check_output(["git", "show", f"{baseline}:{path}"], cwd=ROOT)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline", default="057d78c")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    baseline = subprocess.check_output(["git", "rev-parse", args.baseline], cwd=ROOT, text=True).strip()
    names = subprocess.check_output(["git", "ls-tree", "-r", "--name-only", baseline, "--", SOURCE + "rtl", SOURCE + "constraints"], cwd=ROOT, text=True).splitlines()
    checks = []
    for name in names:
        path = ROOT / name
        if path.suffix.lower() not in (".v", ".vh", ".hex", ".cst", ".sdc"):
            continue
        before = git_bytes(baseline, name).decode("utf-8-sig")
        after = path.read_text(encoding="utf-8-sig")
        if path.suffix.lower() in (".v", ".vh"):
            original, current = rtl_tokens(before), rtl_tokens(after)
            assert original == current, "Effective RTL changed: " + name
            checks.append({"file": name, "comparison": "Verilog tokens", "count": len(current), "result": "PASS"})
        else:
            assert before.replace("\r\n", "\n") == after.replace("\r\n", "\n"), "ROM or constraint changed: " + name
            checks.append({"file": name, "comparison": "text, ignoring platform newlines", "result": "PASS"})
    assert checks, "No baseline RTL found"
    bitstream = ROOT / "releases" / "v1.0.0" / "instrument_sram_0x5633.fs"
    bitstream_sha = hashlib.sha256(bitstream.read_bytes()).hexdigest().upper()
    assert bitstream_sha == "2C7C7001DD3EABF24D2A4ABC2FC93BE1DD441D76812E248B3B84A235DBD22675", "Historical bitstream byte mismatch"
    result = {"result": "PASS", "baseline_commit": baseline, "effective_rtl_unchanged": True, "checks": checks, "historical_bitstream": {"path": str(bitstream.relative_to(ROOT)).replace("\\", "/"), "sha256": bitstream_sha, "historical_user_code": "0x5633", "live_device_read": False}, "simulation_gate_required": True}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"result": "PASS", "files_checked": len(checks), "baseline_commit": baseline, "bitstream_sha256": bitstream_sha}))


if __name__ == "__main__":
    main()
