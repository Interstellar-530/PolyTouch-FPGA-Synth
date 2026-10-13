"""Verify the progress report's dates, workload, key facts, and PDF links."""
from datetime import date, timedelta
from pathlib import Path
import argparse
from decimal import Decimal
import json
import re
from pypdf import PdfReader

ROOT = Path(__file__).resolve().parents[1]
NAME = "FPGA-竞赛差距与执行计划-20261013-v0.1"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("output", nargs="?", type=Path)
    parser.add_argument("--markdown", type=Path, default=ROOT / "docs" / "reviews" / "FPGA-20261013-v0.5" / (NAME + ".md"))
    parser.add_argument("--pdf", type=Path, default=ROOT / "output" / "pdf" / (NAME + ".pdf"))
    parser.add_argument("--expected-pages", type=int, default=10)
    parser.add_argument("--check-ownership", action="store_true")
    args = parser.parse_args()
    md = args.markdown.read_text(encoding="utf-8")
    reader = PdfReader(args.pdf)
    text = re.sub(r"\s+", "", "".join(page.extract_text() for page in reader.pages))
    rows = re.findall(r"^\| [*]*((?:10|11)/\d+)\s+(周[一二三四五六日]) / (\d+) h", md, re.M)
    dates = [date(2026, 10, 13) + timedelta(days=i) for i in range(23)]
    assert len(rows) == 23, "Missing daily plan row"
    assert [row[0] for row in rows] == [f"{day.month:02}/{day.day:02}" for day in dates]
    weekdays = "一二三四五六日"
    assert all(row[1] == "周" + weekdays[day.weekday()] for row, day in zip(rows, dates))
    for day, weekday, hours in rows:
        assert day + weekday + "/" + hours + "h" in text, "Daily row lost in PDF: " + day
    hours = [int(row[2]) for row in rows]
    assert sum(hours[:16]) == 96 and sum(hours[16:]) == 24 and sum(hours) == 120
    task_hours = [int(n) for n in re.findall(r"^\| T\d+[^|]*\|\s*(\d+)\s*\|", md, re.M)]
    assert len(task_hours) == 13 and sum(task_hours) == 120
    critical = ["10月28日为原型机制作与验收DDL", "10月29日至11月4日完整留作视频", "2026年11月4日18:00", "本周日10月18日组装原型机", "九项RTL测试，全部PASS", "12.288MHz", "10kΩ", "FSR402", "本次未确认所购晶振额定电压", "4596/20736", "4/46", "6/24", "208/256", "0x5633", "0xFCF0"]
    for statement in critical:
        if statement == "本次未确认所购晶振额定电压" and "所购晶振额定电压仍未确认" in text:
            continue
        assert statement in text, "Missing critical statement: " + statement
    expected_urls = set(re.findall(r"\]\((https?://[^)]+)\)", md))
    actual_urls = set()
    for page in reader.pages:
        for item in page.get("/Annots", []):
            action = item.get_object().get("/A")
            if action and action.get("/URI"):
                actual_urls.add(str(action["/URI"]))
    assert expected_urls <= actual_urls, "Missing reference link"
    assert len(reader.pages) == args.expected_pages, "Changed pagination needs visual review"
    result = {"result": "PASS", "pages": len(reader.pages), "daily_rows": len(rows), "production_days": 16, "production_hours": 96, "materials_days": 7, "materials_hours": 24, "team_total_hours": 120, "task_hours_total": sum(task_hours), "weekday_and_date_sequence": "PASS", "pdf_daily_rows_retained": "PASS", "critical_statements": len(critical), "clickable_source_urls": len(expected_urls), "visual_review_required": True}
    if args.check_ownership:
        daily_lines = [line for line in md.splitlines() if re.match(r"^\| [*]*(?:10|11)/\d+\s+周", line)]
        onsite_hours, remote_hours = [], []
        for line, row in zip(daily_lines, rows):
            onsite = re.search(r"您（(\d+(?:\.\d+)?)\s*h(?:，现场)?）", line)
            remote = re.search(r"队友（(\d+(?:\.\d+)?)\s*h，(远程|现场)）", line)
            assert onsite and remote, "Missing individual hours: " + row[0]
            assert remote[2] == ("现场" if row[0] == "10/18" else "远程"), "Teammate location mismatch: " + row[0]
            onsite_value, remote_value = Decimal(onsite[1]), Decimal(remote[1])
            assert onsite_value + remote_value == Decimal(row[2]), "Personal workload mismatch: " + row[0]
            onsite_hours.append(onsite_value)
            remote_hours.append(remote_value)
        assert sum(onsite_hours[:16]) == 56 and sum(remote_hours[:16]) == 40
        assert sum(onsite_hours[16:]) == 8 and sum(remote_hours[16:]) == 16
        assert sum(onsite_hours) == 64 and sum(remote_hours) == 56
        assert "所有硬件" in text or "全部外设" in text, "Missing hardware ownership statement"
        for statement in ("队友", "远程", "原始数据", "64", "56"):
            assert statement in text, "Missing ownership statement: " + statement
        result["ownership"] = {"onsite_total": 64, "remote_total": 56, "production_onsite": 56, "production_remote": 40, "materials_onsite": 8, "materials_remote": 16, "all_daily_personal_splits": "PASS"}
    if args.output:
        output = args.output
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
