"""Check the exported report's critical text, pin routes, and clickable sources.

Requires pypdf; visual review of rendered pages remains a separate step.
"""
from pathlib import Path
import csv
import json
import re
import sys

from pypdf import PdfReader

ROOT = Path(__file__).resolve().parents[1]
NAME = "FPGA-硬件连接与软件调研-20261013-v0.1"


def main():
    report = ROOT / "output" / "pdf" / (NAME + ".pdf")
    markdown = report.with_suffix(".md").read_text(encoding="utf-8")
    reader = PdfReader(report)
    compact = re.sub(r"\s+", "", "\n".join(page.extract_text() for page in reader.pages))
    assert len(reader.pages) == 9, "Review changed pagination"

    routes = list(csv.DictReader((ROOT / "docs" / "hardware" / "FPGA-pinplan-20261013-v0.1.csv").open(encoding="utf-8", newline="")))
    assert len(routes) == 21
    for route in routes:
        signal = route["signal"]
        if signal.startswith("key"):
            signal += "，" + route["function"].replace("sharp", "#")
        row = signal + route["connector"] + route["fpga_pin"] + route["bank"]
        assert row in compact, "Missing or changed pin row: " + row

    keys = "A W S E D F T G Y H U J K".split()
    notes = "C4 C#4 D4 D#4 E4 F4 F#4 G4 G#4 A4 A#4 B4 C5".split()
    for key, note, midi in zip(keys, notes, range(60, 73)):
        assert f"{key}{note}{midi}" in compact, "Missing keyboard mapping: " + key

    critical = ["5186020", "0x5633", "0xFCF0", "12.288", "48kHz", "3.072", "250kHz", "768", "208/256", "不是已经生成的32声部硬件结果", "十一只", "数字静音后底噪基本不变"]
    for text in critical:
        assert text in compact, "Missing critical statement: " + text

    expected_urls = set(re.findall(r"\]\((https?://[^)]+)\)", markdown))
    actual_urls = set()
    for page in reader.pages:
        for annotation in page.get("/Annots", []):
            action = annotation.get_object().get("/A")
            if action and action.get("/URI"):
                actual_urls.add(str(action["/URI"]))
    assert expected_urls, "No source links found"
    assert expected_urls <= actual_urls, "Missing clickable source links: " + str(expected_urls - actual_urls)
    assert not any(url.startswith("../") for url in actual_urls), "Nonportable relative link"
    result = {"result": "PASS", "pages": len(reader.pages), "pin_routes_checked": len(routes), "keyboard_mappings_checked": len(keys), "critical_statements_checked": len(critical), "clickable_source_urls_checked": len(expected_urls), "source_urls": sorted(expected_urls), "visual_review_required": True}
    output = Path(sys.argv[1]) if len(sys.argv) > 1 else None
    if output:
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
