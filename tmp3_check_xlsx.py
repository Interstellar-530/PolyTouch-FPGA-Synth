from openpyxl import load_workbook
p = r"E:\Working Space\FPGA\docs\planning\外设采购清单-20261010.xlsx"
wb = load_workbook(p)
print("sheets:", wb.sheetnames)
ws = wb["待采购清单"]
print("dims:", ws.dimensions)
for row in ws.iter_rows(min_row=3, max_row=ws.max_row, max_col=9, values_only=True):
    print(" | ".join("" if v is None else str(v) for v in row))
