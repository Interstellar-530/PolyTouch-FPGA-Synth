"""Verify the progress report's dates, workload, key facts, and PDF links."""
from datetime import date, timedelta
from pathlib import Path
import json
import re
import sys
from pypdf import PdfReader

ROOT = Path(__file__).resolve().parents[1]
NAME = "FPGA-竞赛差距与执行计划-20261013-v0.1"


def main():
    md = (ROOT / "docs" / "reviews" / "FPGA-20261013-v0.5" / (NAME + ".md")).read_text(encoding="utf-8")
    reader = PdfReader(ROOT / "output" / "pdf" / (NAME + ".pdf"))
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
        assert statement in text, "Missing critical statement: " + statement
    expected_urls = set(re.findall(r"\]\((https?://[^)]+)\)", md))
    actual_urls = set()
    for page in reader.pages:
        for item in page.get("/Annots", []):
            action = item.get_object().get("/A")
            if action and action.get("/URI"):
                actual_urls.add(str(action["/URI"]))
    assert expected_urls <= actual_urls, "Missing reference link"
    assert len(reader.pages) == 10, "Changed pagination needs visual review"
    result = {"result": "PASS", "pages": len(reader.pages), "daily_rows": len(rows), "production_days": 16, "production_hours": 96, "materials_days": 7, "materials_hours": 24, "team_total_hours": 120, "task_hours_total": sum(task_hours), "weekday_and_date_sequence": "PASS", "pdf_daily_rows_retained": "PASS", "critical_statements": len(critical), "clickable_source_urls": len(expected_urls), "visual_review_required": True}
    if len(sys.argv) > 1:
        output = Path(sys.argv[1])
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
