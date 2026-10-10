import pymupdf
doc = pymupdf.open(r"E:\Working Space\FPGA\docs\references\Tang_Primer_20K_Dock_3714_Schematics.pdf")
print("pages:", len(doc))
for pno in range(len(doc)):
    words = doc[pno].get_text("words")
    hits = [w for w in words if any(k in w[4].upper() for k in ("FT2","FT22","2232","UART1","USB-JTAG","BL702","CH340","CP210"))]
    if not hits: continue
    print(f"--- page {pno+1} ---")
    for w in hits[:40]:
        band=[x for x in words if abs(((x[1]+x[3])/2)-((w[1]+w[3])/2))<5 and x[0]>w[2]+1 and x[0]<w[2]+150]
        band.sort(key=lambda x:x[0])
        print(f"   y={w[1]:6.1f} {w[4]:16s} -> {' '.join(x[4] for x in band)[:90]}")
