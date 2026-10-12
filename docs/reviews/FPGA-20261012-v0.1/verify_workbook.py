"""Validate the exported file without writing or changing it."""
import json
import sys
from pathlib import Path

import openpyxl

package = Path(__file__).resolve().parent
target = package / "FPGA外设复查清单-20261012-v0.1.xlsx"
values = openpyxl.load_workbook(target, data_only=True)
formulas = openpyxl.load_workbook(target, data_only=False)
assert values.sheetnames == ["采购清单", "板载资源与复查"]
sheet = values["采购清单"]
assert sheet["A9"].value == "P01" and sheet["A38"].value == "P30"
assert sheet["G5"].value == 508 and sheet["G6"].value == 241
assert sheet["D9"].value == 1  # Restored after the editable-input test.
for row in range(9, 39):
    qty, price, subtotal = (sheet.cell(row, col).value for col in (4, 6, 7))
    assert isinstance(qty, (int, float)) and qty > 0
    if price is None:
        assert subtotal in (None, "")
    else:
        assert isinstance(price, (int, float))
        assert abs(subtotal - qty * price) < 1e-9
assert formulas["采购清单"]["G38"].value == '=IF(F38="","",D38*F38)'
assert formulas["采购清单"].freeze_panes == "D9"
assert "Peripherals" in formulas["采购清单"].tables
assert len(formulas["采购清单"].data_validations.dataValidation) == 1
assert values["板载资源与复查"]["B12"].value == "J14第10脚→MIC_DAT3→T7/GCLKT_3"
print(json.dumps({"result": "PASS", "items": 30, "total_cny": 508,
                  "p0_cny": 241, "formula_caches_checked": True,
                  "tables_and_dropdown_checked": True,
                  "native_excel_application_tested": False}, ensure_ascii=False))
