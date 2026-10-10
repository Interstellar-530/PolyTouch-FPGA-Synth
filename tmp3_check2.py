from openpyxl import load_workbook
p = r"E:\Working Space\FPGA\docs\planning\外设采购清单-20261010.xlsx"
wb = load_workbook(p)
out = []
out.append("sheets: " + ", ".join(wb.sheetnames))
for name in wb.sheetnames:
    ws = wb[name]
    out.append(f"[{name}] dims={ws.dimensions} rows={ws.max_row} cols={ws.max_column}")
ws = wb["待采购清单"]
for row in ws.iter_rows(min_row=3, max_row=ws.max_row, max_col=9, values_only=True):
    out.append(" | ".join("" if v is None else str(v) for v in row))
open(r"E:\Working Space\FPGA\tmp3_xlsx_dump.txt","w",encoding="utf-8").write("\n".join(out))
