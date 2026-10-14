"""Export a pinned Git release with file checksums and no runtime caches."""
from pathlib import Path
import argparse
import hashlib
import io
import json
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--ref", required=True)
    parser.add_argument("--release", default="v1.0.0", choices=("v1.0.0", "v1.01"))
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    commit = subprocess.check_output(["git", "rev-parse", args.ref + "^{commit}"], cwd=ROOT, text=True).strip()
    names = subprocess.check_output(["git", "-c", "core.quotepath=false", "ls-tree", "-r", "--name-only", args.ref], cwd=ROOT, text=True, encoding="utf-8").splitlines()
    selected = []
    for name in names:
        if name in ("README.md", ".gitattributes", "AGENTS.md"):
            selected.append(name)
        elif name.startswith("output/handoff_milestone2_20261008/source/") and Path(name).suffix in (".v", ".vh", ".hex", ".cst", ".sdc", ".ps1", ".tcl", ".py", ".md"):
            selected.append(name)
        elif name.startswith("tools/serial_keyboard/"):
            selected.append(name)
        elif name in ("tools/verify_release_rtl.py", "tools/build_release_package.py", "docs/handoff/FPGA-队友仿真环境配置提示词-20261013-v0.1.md"):
            selected.append(name)
        elif name.startswith("docs/releases/v1.0.0") or name.startswith("releases/v1.0.0/"):
            selected.append(name)
        elif args.release == "v1.01" and (
            name in ("tools/analyze_audio_capture.py", "tools/run_audio_verification.ps1",
                     "docs/evidence/FPGA-S1-音频验收-20261014-v0.1.md",
                     "docs/logs/FPGA_DEBUG_LOG_20261014_V1_FLASH.md",
                     "docs/planning/FPGA-缺件期间仿真与算法任务-20261013-v0.1.md")
            or name.startswith("tools/audio_capture/") or name.startswith("docs/releases/v1.01")
        ):
            selected.append(name)
    assert selected and "releases/v1.0.0/instrument_sram_0x5633.fs" in selected
    # Git supplies canonical committed bytes; avoid worktree newline conversion.
    exported = subprocess.check_output(["git", "archive", "--format=zip", args.ref, "--"] + selected, cwd=ROOT)
    if args.release == "v1.01":
        for required in ("tools/analyze_audio_capture.py", "tools/run_audio_verification.ps1",
                         "tools/audio_capture/requirements.txt", "docs/releases/v1.01.md",
                         "output/handoff_milestone2_20261008/source/sim/tb_audio_capture.v"):
            assert required in selected, "Missing S1 release input: " + required
    prefix = "PolyTouch-" + args.release + "/"
    sha_lines = []
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(io.BytesIO(exported)) as original, zipfile.ZipFile(args.output, "w", zipfile.ZIP_DEFLATED) as package:
        for item in original.infolist():
            if item.is_dir():
                continue
            payload = original.read(item.filename)
            package.writestr(prefix + item.filename, payload)
            sha_lines.append(hashlib.sha256(payload).hexdigest() + "  " + item.filename)
        info = {"release": args.release, "git_ref": args.ref, "git_commit": commit, "file_count": len(sha_lines), "source_root": "output/handoff_milestone2_20261008/source", "historical_sram_user_code": "0x5633", "bitstream_sha256": "2C7C7001DD3EABF24D2A4ABC2FC93BE1DD441D76812E248B3B84A235DBD22675", "runtime_dependencies": "Windows PowerShell 5.1, Icarus; Gowin for rebuilding/programming"}
        if args.release == "v1.01":
            info.update(production_rtl_baseline="v1.0.0", rtl_test_count=10,
                        s1_requirements="tools/audio_capture/requirements.txt",
                        runtime_dependencies="Windows PowerShell 5.1, Icarus; Python/NumPy/Matplotlib for offline S1 analysis; Gowin for rebuilding/programming")
        package.writestr(prefix + "PACKAGE_MANIFEST.json", json.dumps(info, ensure_ascii=False, indent=2) + "\n")
        package.writestr(prefix + "checksums.sha256", "\n".join(sha_lines) + "\n")
    # Verify the produced archive rather than merely trusting archive creation.
    with zipfile.ZipFile(args.output) as package:
        assert package.testzip() is None, "Zip CRC mismatch"
        for line in sha_lines:
            digest, name = line.split("  ", 1)
            assert hashlib.sha256(package.read(prefix + name)).hexdigest() == digest
        image = package.read(prefix + "releases/v1.0.0/instrument_sram_0x5633.fs")
        assert hashlib.sha256(image).hexdigest().upper() == info["bitstream_sha256"]
    package_sha = hashlib.sha256(args.output.read_bytes()).hexdigest()
    args.output.with_suffix(".zip.sha256").write_text(package_sha + "  " + args.output.name + "\n", encoding="ascii")
    print(json.dumps({"result": "PASS", "git_commit": commit, "file_count": len(sha_lines), "package": str(args.output), "sha256": package_sha}, ensure_ascii=False))


if __name__ == "__main__":
    main()
