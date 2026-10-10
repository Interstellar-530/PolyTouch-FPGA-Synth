from openpyxl import load_workbook
p = r"E:\Working Space\FPGA\docs\planning\外设采购清单-20261010.xlsx"
wb = load_workbook(p)
ws = wb["待采购清单"]
for row in ws.iter_rows(min_row=5, max_row=ws.max_row, max_col=3):
    if row[2].value and "转接小" in str(row[2].value):
        row[2].value = str(row[2].value).replace("转接小", "转接板")
wb.save(p)
print("typo fixed")
