# -*- coding: utf-8 -*-
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from openpyxl.utils import get_column_letter

wb = Workbook()

HDR_FILL = PatternFill("solid", fgColor="1F4E79")
HDR_FONT = Font(color="FFFFFF", bold=True, size=11)
CAT_FILL = PatternFill("solid", fgColor="DDEBF7")
P0_FILL  = PatternFill("solid", fgColor="FCE4D6")
GREY     = PatternFill("solid", fgColor="F2F2F2")
thin = Side(style="thin", color="BFBFBF")
BORDER = Border(left=thin, right=thin, top=thin, bottom=thin)
WRAP = Alignment(wrap_text=True, vertical="top")

# ---------------- Sheet 1: what still has to be bought or borrowed ----------
ws = wb.active
ws.title = "待采购清单"

ws["A1"] = "PolyTouch FPGA Synth 外设清单（2026-10-10）"
ws["A1"].font = Font(bold=True, size=14, color="1F4E79")
ws["A2"] = "已扣除 Tang Primer 20K 核心板 + Dock 3714 自带的外设。标注“实验室”的项建议先在实验室借用，确认可用后再决定是否自购。"
ws["A2"].font = Font(size=10, color="595959")
ws.merge_cells("A1:I1"); ws.merge_cells("A2:I2")
ws["A2"].alignment = WRAP

headers = ["序号", "类别", "物品", "数量", "用途", "优先级", "获取方式", "参考单价(元)", "预计小计(元)"]
ws.append([])
ws.append(headers)
hdr_row = ws.max_row
for c in range(1, len(headers) + 1):
    cell = ws.cell(row=hdr_row, column=c)
    cell.fill = HDR_FILL; cell.font = HDR_FONT
    cell.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)
    cell.border = BORDER

rows = [
    ("演奏输入", "MPR121 电容触摸模块（12 通道，I2C，3.3 V）", "1 块", "第一演奏维度：12 个触摸键", "P0", "自行购买", 12, 12),
    ("演奏输入", "触摸电极材料（铜箔胶带/导电布/弹簧片 + 细导线）", "12 套", "接在 MPR121 的 12 个通道上做成键盘", "P0", "自行购买", 3, 36),
    ("演奏输入", "FSR 402 压力传感器", "1 个", "第二演奏维度：力度或持续音量", "P0", "自行购买", 20, 20),
    ("演奏输入", "10 kΩ 金属膜电阻（FSR 分压用）", "10 个", "与 FSR 组成分压，接到 MCP3208", "P0", "自行购买", 0.3, 3),
    ("采样", "MCP3208 12 位 8 通道 SPI ADC 模块", "1 块", "读 FSR 压力值", "P0", "自行购买", 20, 20),
    ("正式音频输出", "PCM5102A I2S DAC 模块", "1 块", "赛题要求的正式音频出口，替代 PT8211 调试口", "P0", "自行购买", 35, 35),
    ("正式音频输出", "12.288 MHz 3.3 V 有源晶振（含转接小）", "1 个（建议备 1）", "产生标准 48 kHz 与 I2S 时钟", "P0", "自行购买", 15, 15),
    ("连线与供电", "面包板 830 孔", "2 块", "搭 MPR121、MCP3208、PCM5102A 电路", "P0", "自行购买", 20, 40),
    ("连线与供电", "杜邦线套装（公对母/母对母/公对公）", "各 1 包", "板到面包板连线", "P0", "自行购买", 20, 20),
    ("连线与供电", "去耦电容与电阻包（100 nF、1 µF、22~100 Ω、4.7 kΩ）", "1 套", "电源去耦、时钟串阻、I2C 上拉", "P0", "自行购买", 15, 15),
    ("连线与供电", "独立 5 V/2 A USB 电源或充电宝", "1 个", "与电脑断开地环路，压底噪；给外设供电", "P0", "实验室/自有", 0, 0),
    ("调试", "数字万用表", "1 台", "量 Bank 电压、共地、分压", "P0", "实验室", 0, 0),
    ("调试", "USB 逻辑分析仪（24 MHz 8 通道）", "1 台", "抓 I2C/SPI/I2S/UART，验证触摸与 ADC 真的通了", "P1", "实验室/自行购买", 50, 50),
    ("调试", "3.5 mm 立体声公对公音频线", "1 根", "接耳机或音箱", "P1", "自行购买", 10, 10),
    ("调试", "3.5 mm 转电脑声卡输入线", "1 根", "把输出接进电脑声卡，看频谱做现场证据", "P1", "自行购买", 20, 20),
    ("调试", "示波器（≥50 MHz）", "1 台", "看 I2S 波形与模拟输出噪声", "P2", "实验室", 0, 0),
    ("调试", "可调直流电源 / 焊台", "1 套", "焊接与供电调试", "P2", "实验室", 0, 0),
    ("可选增强", "旋转编码器 EC11", "2 个", "调总音量、音色、效果量", "P2", "自行购买", 5, 10),
    ("可选增强", "SPI OLED 0.96 寸", "1 块", "显示音高、声部数、延迟", "P2", "自行购买", 15, 15),
    ("可选增强", "WS2812 灯带", "1 条", "硬件可视化（板上已有 1 颗可先验证）", "P2", "自行购买", 15, 15),
    ("可选增强", "DIN MIDI 插座 + 6N138 光耦", "1 套", "标准 MIDI 键盘输入", "P2", "自行购买", 10, 10),
    ("可选增强", "第二片 MPR121", "1 块", "扩到 24 键", "P2", "自行购买", 12, 12),
]

r = hdr_row + 1
for i, (cat, item, qty, use, prio, src, unit, sub) in enumerate(rows, start=1):
    ws.cell(row=r, column=1, value=i)
    ws.cell(row=r, column=2, value=cat)
    ws.cell(row=r, column=3, value=item)
    ws.cell(row=r, column=4, value=qty)
    ws.cell(row=r, column=5, value=use)
    ws.cell(row=r, column=6, value=prio)
    ws.cell(row=r, column=7, value=src)
    ws.cell(row=r, column=8, value=unit)
    ws.cell(row=r, column=9, value=sub)
    for c in range(1, 10):
        cell = ws.cell(row=r, column=c)
        cell.border = BORDER
        cell.alignment = WRAP if c in (3, 5) else Alignment(horizontal="center", vertical="center")
    if prio == "P0":
        ws.cell(row=r, column=6).fill = P0_FILL
    ws.cell(row=r, column=2).fill = GREY
    ws.cell(row=r, column=8).number_format = "#,##0.0"
    ws.cell(row=r, column=9).number_format = "#,##0.0"
    r += 1

last = r - 1
ws.cell(row=r, column=3, value="合计（自行购买部分）").font = Font(bold=True)
ws.cell(row=r, column=9, value=f"=SUM(I{hdr_row+1}:I{last})").font = Font(bold=True)
ws.cell(row=r, column=9).number_format = "#,##0.0"
ws.cell(row=r+1, column=3, value="其中 P0 必需项").font = Font(bold=True)
ws.cell(row=r+1, column=9, value=f'=SUMIFS(I{hdr_row+1}:I{last},F{hdr_row+1}:F{last},"P0")').font = Font(bold=True)
ws.cell(row=r+1, column=9).number_format = "#,##0.0"
for rr in (r, r+1):
    for c in range(1, 10):
        ws.cell(row=rr, column=c).fill = CAT_FILL
        ws.cell(row=rr, column=c).border = BORDER

widths = [6, 14, 42, 14, 40, 8, 14, 12, 12]
for i, w in enumerate(widths, start=1):
    ws.column_dimensions[get_column_letter(i)].width = w
ws.freeze_panes = ws.cell(row=hdr_row + 1, column=1)
ws.row_dimensions[hdr_row].height = 28

# ---------------- Sheet 2: what was crossed off ----------------------------
ws2 = wb.create_sheet("已划去-板上已含")
ws2["A1"] = "Tang Primer 20K 核心板 + Dock 3714 已经包含的外设，不再需要购买"
ws2["A1"].font = Font(bold=True, size=13, color="1F4E79")
ws2.merge_cells("A1:D1")
ws2.append([])
h2 = ["来源", "已包含的外设", "说明", "对应原清单里被划去的项"]
ws2.append(h2)
for c in range(1, 5):
    cell = ws2.cell(row=3, column=c)
    cell.fill = HDR_FILL; cell.font = HDR_FONT
    cell.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)
    cell.border = BORDER

rows2 = [
    ("核心板", "GW2A-LV18PG256C8/I7 主控", "赛题要求的高云 FPGA 本体", "主控板卡"),
    ("核心板", "64 MB DDR3 / 板载 SPI Flash / microSD 卡座", "配置存储与可选数据缓存", "存储、配置 Flash"),
    ("核心板", "27 MHz 板载晶振", "当前 PT8211 调试通路的时钟源", "板载时钟"),
    ("Dock", "PT8211-S DAC + LPA4809MSF 耳机功放 + 3.5 mm 耳机座", "当前调试发声通路，正式版本改用外接 PCM5102A", "耳机接口、调试 DAC、功放"),
    ("Dock", "6 个用户 LED（Orange_LED0~5）", "状态指示、可视化雏形", "状态指示灯"),
    ("Dock", "1 颗 WS2812 RGB LED", "板载可视化，增强项可先用它验证", "WS2812 灯带（可先用板载这 1 颗）"),
    ("Dock", "6 个按键（1 个 BL702 烧录键 + 5 个用户键 S0~S4）", "S1/S2 已用作音调切换，S3 用作同步复位，S4 是 RECONFIG_N 不可用", "用户按键、复位按键"),
    ("Dock", "5 位拨码开关 + 1 个滑动开关", "使能核心板与切换板载 USB 功能", "拨码开关、模式开关"),
    ("Dock", "4 个 PMOD 扩展口（2.54 mm 排针）", "可直接插杜邦线，不需要额外的 PMOD 转接板", "PMOD 转接板"),
    ("Dock", "USB-JTAG&UART (BL702) Type-C + 自定义 USB Type-C", "提供下载与串口桥", "USB 下载/串口模块"),
    ("Dock", "12 V DC 输入座 + 板载 5 V / +3V3 / +1V5 电源", "常规调试可直接用 Type-C 供电", "板载电源"),
    ("Dock", "HDMI、千兆以太网（RTL8201F）", "暂未使用，可作为后续上位机通路备选", "网络接口"),
    ("Dock", "RGB LCD 40P FPC、DVP 摄像头 24P FPC、麦克风阵列 10P FPC、TP 触摸 6P FPC", "接口在板上，但配套面板/摄像头需另购；本项目用 MPR121 方案绕开 TP 口", "显示/摄像头/触摸面板"),
    ("随板附件", "Gowin USB 下载器（FT2CH，FTDI 双通道）", "本机已识别为 COM13，可正常读取器件 ID", "高云下载器 / 编程器"),
    ("本机软件", "Arduino IDE 与 FTDI 驱动", "Arduino IDE 自带串口监视器可作备用串口平台", "串口调试软件"),
]
r = 4
for row in rows2:
    for c, v in enumerate(row, start=1):
        cell = ws2.cell(row=r, column=c, value=v)
        cell.border = BORDER
        cell.alignment = WRAP if c in (2, 3, 4) else Alignment(horizontal="center", vertical="center")
    r += 1
for i, w in enumerate([10, 46, 52, 40], start=1):
    ws2.column_dimensions[get_column_letter(i)].width = w
ws2.freeze_panes = "A4"

# ---------------- Sheet 3: notes ------------------------------------------
ws3 = wb.create_sheet("说明")
notes = [
    ("清单口径", "只列出当前确实需要自行购买或到实验室借用的设备；板上已有的外设全部划到“已划去-板上已含”页。"),
    ("为什么还要买 PCM5102A", "板载 PT8211 是“Japanese”右对齐格式，不是标准 I2S。赛题要求 I2S 接口输出到 DAC，所以正式版本必须外接 PCM5102A，PT8211 只留作调试。"),
    ("为什么还要买 12.288 MHz 晶振", "板载 27 MHz 无法用整数分频得到 12.288 MHz（比值 512/1125）。标准 48 kHz 与 I2S 时钟需要独立晶振。"),
    ("为什么先不买效果器相关器件", "效果器、第二音色属于扩展项，等 4 声部和触摸调通、资源账算清楚后再决定。"),
    ("价格说明", "单价是淘宝散件的常见量级，只做预算参考；同款差异可能达一倍。"),
    ("优先顺序", "P0 = 下一阶段（4 声部 + 触摸 + 力度）必需；P1 = 做现场证据和正式接口必需；P2 = 有余力再做。"),
    ("数据来源", "板上外设依据 Dock 3714 原理图、SOM-3961 原理图与 Sipeed 官方 wiki 的规格对比表核对。"),
]
ws3["A1"] = "说明"; ws3["A1"].font = Font(bold=True, size=13, color="1F4E79")
ws3.append([])
r = 3
for k, v in notes:
    ws3.cell(row=r, column=1, value=k).font = Font(bold=True)
    ws3.cell(row=r, column=2, value=v).alignment = WRAP
    ws3.cell(row=r, column=1).border = BORDER
    ws3.cell(row=r, column=2).border = BORDER
    r += 1
ws3.column_dimensions["A"].width = 24
ws3.column_dimensions["B"].width = 90

out = r"E:\Working Space\FPGA\docs\planning\外设采购清单-20261010.xlsx"
wb.save(out)
print("saved", out)
