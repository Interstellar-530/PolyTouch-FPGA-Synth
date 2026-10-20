# -*- coding: utf-8 -*-
"""Generate the Taobao purchase-link list (Markdown + HTML).

Taobao item pages cannot be fetched without a logged-in session, so each row
links to a Taobao search page built from a precise keyword instead of a single
listing. Search pages stay valid as listings change.

Usage:
    python tools/make_purchase_links.py --outdir docs/planning
"""
import argparse
import html
import os
import sys
import urllib.parse

DATE = "20261012"
VERSION = "v0.1"
BASENAME = "FPGA淘宝采购链接-%s-%s" % (DATE, VERSION)

# id, category, item, qty, unit, status, keyword, note
ITEMS = [
    ("P01", "演奏输入", "MPR121 12路电容触摸模块", "1", "块", "已购",
     "MPR121 电容触摸模块 12路 I2C",
     "确认模块自带 I2C 上拉、ADDR 跳线位置；3.3V 供电"),
    ("P02", "演奏输入", "触摸电极与细导线", "12", "套", "需补购",
     "铜箔胶带 导电 自粘",
     "12 路电极可用铜箔胶带或导电布；引线越短越好，避开 I2C/SPI 走线"),
    ("P02-2", "演奏输入", "电极引线（细电子线）", "1", "套", "需补购",
     "电子线 单芯 0.5mm 多色 导线",
     "MPR121 模块只带排针，电极到模块的引线要细、要短，单根不超过 200mm"),
    ("P02-3", "演奏输入", "导电布电极（可选替代）", "1", "卷", "需补购",
     "导电布 胶带 电磁屏蔽",
     "和铜箔二选一，电极面积大些更灵敏"),
    ("P03", "演奏输入", "FSR402 压力传感器", "1", "个", "已购",
     "FSR402 压力传感器 薄膜",
     "响应非线性，只作相对力度标定"),
    ("P04", "演奏输入", "10kΩ 分压电阻", "10", "个", "需补购",
     "金属膜电阻 10K 1/4W 100只",
     "与 FSR 组成分压；也可直接买常用阻值电阻包"),
    ("P05", "演奏输入", "MCP3208 12位 SPI ADC", "1", "块", "已购",
     "MCP3208 ADC 模块 12位 SPI",
     "VDD/VREF 都接 3.3V；SPI 先跑 1MHz"),
    ("P06", "正式音频", "PCM5102A I2S DAC 模块", "1", "块", "已购",
     "PCM5102A I2S DAC 模块",
     "FMT 跳线选标准 I2S；线路输出接有源音箱或耳放"),
    ("P07", "正式音频", "12.288MHz 有源晶振及转接", "1", "套", "已购",
     "12.288MHz 有源晶振 3.3V 贴片",
     "配套买贴片转 DIP 转接板；输出串 22~100Ω"),
    ("P08", "正式音频", "耳机功放模块", "1", "块", "已购",
     "耳机功放模块 3.5mm 立体声",
     "PCM5102A 是线路输出，接无源耳机必须经功放"),
    ("P09", "第三维控制", "B10K 线性电位器及旋钮", "1", "套", "已购",
     "B10K 电位器 单联 线性 旋钮",
     "接 MCP3208 通道 1，做连续控制量"),
    ("P10", "连接供电", "830 孔面包板", "1", "块", "已购",
     "面包板 830孔 免焊",
     "电极引线和 FSR 分压先在面包板上验证"),
    ("P11", "连接供电", "杜邦线综合套装", "1", "套", "需补购",
     "杜邦线 套装 公对母 母对母 公对公",
     "三种接头都要；母对母用于接开发板排针"),
    ("P12", "连接供电", "去耦电容与串阻套装", "1", "套", "需补购",
     "独石电容包 100nF 1uF 30种",
     "另需 22~100Ω 串阻和 4.7kΩ 上拉；可买常用阻值包补齐"),
    ("P13", "连接供电", "5V/2A USB 电源或充电宝", "1", "个", "自有或借用",
     "USB充电器 5V 2A",
     "断开与电脑共地时用，做底噪对照"),
    ("P14", "调试证据", "数字万用表", "1", "台", "实验室借用",
     "数字万用表 自动量程",
     "确认 3.3V/1.5V 电源域和分压比"),
    ("P15", "调试证据", "8 通道 USB 逻辑分析仪", "1", "台", "实验室借用",
     "逻辑分析仪 8通道 24M USB",
     "抓 I2C/SPI/I2S 波形；板内 GAO 只能看数字状态"),
    ("P16", "调试证据", "3.5mm 立体声音频线", "1", "根", "已购",
     "3.5mm 音频线 双公头 立体声",
     "接电脑声卡输入看频谱"),
    ("P17", "调试证据", "USB 声卡（真正线路输入）", "1", "个", "已购",
     "USB声卡 线路输入",
     "录音关闭 AGC 再测谐波和底噪"),
    ("P18", "调试证据", "线路输入衰减连接组件", "1", "套", "条件采购",
     "音频衰减器 3.5mm 无源",
     "线路输入实测削波时再加"),
    ("P19", "调试证据", "≥50MHz 示波器", "1", "台", "实验室借用",
     "示波器 50MHz 双通道",
     "看模拟噪声、输出边沿和总延迟"),
    ("P20", "调试证据", "焊台与焊接耗材", "1", "套", "实验室借用",
     "焊台 恒温 电烙铁 套装",
     "焊接晶振转接板、排针和固定接线"),
    ("P21", "结构固定", "洞洞板、底板及紧固件", "1", "套", "后续需要",
     "洞洞板 万用板 5x7",
     "另配 M3 铜柱螺丝套装固定电极和压力垫"),
    ("P22", "备用件", "12.288MHz 晶振备用套装", "1", "套", "暂缓",
     "12.288MHz 有源晶振 3.3V 贴片",
     "随 P07 一起决定是否备件"),
    ("P23", "可选扩展", "EC11 旋转编码器", "2", "个", "暂缓",
     "EC11 旋转编码器 带旋钮 20位",
     "先用板载按键和串口调参"),
    ("P24", "可选扩展", "0.96 寸 SPI OLED", "1", "块", "暂缓",
     "0.96寸 OLED SPI 模块 7针",
     "板载 6 个 LED 加 WS2812B 已够状态反馈"),
    ("P25", "可选扩展", "12 灯 WS2812 灯带", "1", "条", "暂缓",
     "WS2812B 灯带 12灯 5V",
     "逐键灯效才需要"),
    ("P26", "可选扩展", "74AHCT 电平转换小板", "1", "块", "暂缓",
     "74AHCT125 电平转换 模块",
     "仅外接 5V 灯带时评估"),
    ("P27", "可选扩展", "DIN MIDI 输入及 6N138 组件", "1", "套", "暂缓",
     "MIDI 插座 5针 DIN 180度",
     "另配 6N138 光耦和限流电阻"),
    ("P28", "可选扩展", "第二片 MPR121 模块", "1", "块", "暂缓",
     "MPR121 电容触摸模块 12路 I2C",
     "扩到 24 键时再买，注意 I2C 地址跳线"),
    ("P29", "可选供电", "12V 直流适配器", "1", "个", "自有或借用",
     "12V 2A 电源适配器 5.5*2.1",
     "只接底板 J13，插头极性和尺寸实物核对"),
    ("P30", "可选声音", "有源音箱", "1", "套", "自有或借用",
     "有源音箱 3.5mm 桌面",
     "可替代 P08 耳机功放，不重复计采购"),
]

STATUS_ORDER = ["需补购", "后续需要", "条件采购", "实验室借用", "自有或借用", "暂缓", "已购"]


def search_url(keyword):
    return "https://s.taobao.com/search?q=" + urllib.parse.quote(keyword, safe="")


def build_markdown():
    lines = []
    lines.append("# 淘宝采购链接清单（%s-%s）" % (DATE, VERSION))
    lines.append("")
    lines.append(
        "本清单为 Tang Primer 20K Dock 3714 电子乐器项目的外设采购链接。淘宝商品页在未登录状态下"
        "会被反爬拦截，也无法被搜索引擎收录，因此每行给的是按精确关键词生成的淘宝搜索页链接，"
        "点开后即为当前在售商品，价格和店铺随行就市。"
    )
    lines.append("")
    lines.append("状态一列中，已购表示你已经在到货的清单上打勾；需补购是当前还缺的；其余按备注处理。")
    lines.append("")
    lines.append("## 1. 当前需要补购")
    lines.append("")
    lines.append("| 编号 | 元件 | 数量 | 关键词 | 链接 |")
    lines.append("| --- | --- | --- | --- | --- |")
    for item in ITEMS:
        if item[5] != "需补购":
            continue
        lines.append(
            "| %s | %s | %s %s | %s | [淘宝搜索](%s) |"
            % (item[0], item[2], item[3], item[4], item[6], search_url(item[6]))
        )
    lines.append("")
    lines.append(
        "按清单里的预算单价，这组补购件合计约 74 元：触摸电极 36 元、10kΩ 电阻 3 元、"
        "杜邦线 20 元、去耦电容与串阻 15 元。电极引线和导电布按现有库存决定是否加买。"
    )
    lines.append("")
    lines.append("## 2. 全部条目")
    lines.append("")
    lines.append("| 编号 | 类别 | 元件 | 数量 | 状态 | 淘宝关键词 | 链接 | 选型要点 |")
    lines.append("| --- | --- | --- | --- | --- | --- | --- | --- |")
    for item in ITEMS:
        lines.append(
            "| %s | %s | %s | %s %s | %s | %s | [搜索](%s) | %s |"
            % (item[0], item[1], item[2], item[3], item[4], item[5], item[6],
               search_url(item[6]), item[7])
        )
    lines.append("")
    lines.append("## 3. 采购提示")
    lines.append("")
    lines.append(
        "淘宝搜索页支持按销量排序，模块类商品优先选销量高、带原理图或资料链接的店铺。"
        "MPR121 和 PCM5102A 这类模块，下单前向客服确认芯片型号、供电电压和跳线默认状态，"
        "到手后再按硬件控制信号文档逐项核对。"
    )
    lines.append("")
    lines.append("关键词里带具体型号的条目，如果搜出来结果太杂，可以把关键词再缩短到型号本身，"
        "例如只搜 MPR121 或 PCM5102A。")
    lines.append("")
    lines.append("生成方式：`python tools/make_purchase_links.py --outdir docs/planning`。")
    lines.append("")
    return "\n".join(lines)


def build_html():
    rows = []
    for item in ITEMS:
        status_class = "s-todo" if item[5] == "需补购" else (
            "s-later" if item[5] in ("后续需要", "条件采购") else (
                "s-have" if item[5] == "已购" else "s-borrow"))
        rows.append(
            "<tr class='%s'><td>%s</td><td>%s</td><td>%s</td><td>%s %s</td>"
            "<td>%s</td><td><a href='%s' target='_blank' rel='noreferrer'>%s</a></td><td>%s</td></tr>"
            % (status_class, item[0], item[1], html.escape(item[2]), item[3], item[4],
               html.escape(item[5]), html.escape(search_url(item[6]), quote=True),
               html.escape(item[6]), html.escape(item[7]))
        )

    todo = [i for i in ITEMS if i[5] == "需补购"]
    todo_rows = []
    for item in todo:
        todo_rows.append(
            "<li><a href='%s' target='_blank' rel='noreferrer'>%s</a>（%s %s）</li>"
            % (html.escape(search_url(item[6]), quote=True), html.escape(item[2]),
               item[3], item[4])
        )

    return """<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<title>淘宝采购链接清单 %s-%s</title>
<style>
body { font-family: "Microsoft YaHei", "Segoe UI", sans-serif; margin: 32px auto; max-width: 1180px;
       line-height: 1.75; color: #1f2328; }
h1 { font-size: 25px; margin-bottom: 6px; }
h2 { font-size: 19px; margin-top: 30px; border-left: 4px solid #7a4bbf; padding-left: 10px; }
p  { margin: 10px 0; }
table { border-collapse: collapse; width: 100%%; margin: 12px 0 22px; font-size: 14px; }
th, td { border: 1px solid #d8dbe0; padding: 7px 9px; vertical-align: top; text-align: left; }
th { background: #f3f0fa; font-weight: 600; }
tr.s-todo   { background: #fff6e0; }
tr.s-later  { background: #f6f8fa; }
tr.s-have   { color: #6b7280; }
tr.s-borrow { background: #f6f8fa; color: #6b7280; }
a { color: #1a5fb4; }
ul { margin: 8px 0 18px 20px; }
code { background: #f3f4f6; padding: 1px 5px; border-radius: 4px; }
</style>
</head>
<body>
<h1>淘宝采购链接清单（%s-%s）</h1>
<p>Tang Primer 20K Dock 3714 电子乐器项目的外设采购链接。淘宝商品页在未登录状态下会被反爬拦截，
搜索引擎也不收录商品页，所以这里给出的是按精确关键词生成的淘宝搜索页链接，点开就是当前在售商品，
价格与店铺随行就市。表格里浅黄色是现在需要补购的，灰色是可以缓办或已够用的。</p>
<h2>1. 当前需要补购</h2>
<ul>
%s
</ul>
<p>按清单里的预算单价，这组补购件合计约 74 元：触摸电极 36 元、10kΩ 电阻 3 元、
杜邦线 20 元、去耦电容与串阻 15 元。电极引线和导电布按现有库存决定是否加买。</p>
<h2>2. 全部条目</h2>
<table>
<tr><th>编号</th><th>类别</th><th>元件</th><th>数量</th><th>状态</th><th>淘宝关键词</th><th>选型要点</th></tr>
%s
</table>
<h2>3. 采购提示</h2>
<p>淘宝搜索页可以按销量排序，模块类优先选销量高、带资料链接的店铺。MPR121 和 PCM5102A
这类模块，下单前让客服确认芯片型号、供电电压和跳线默认状态。关键词如果搜出来太杂，直接缩到型号本身，
例如只搜 MPR121 或 PCM5102A。生成方式：<code>python tools/make_purchase_links.py --outdir docs/planning</code></p>
</body>
</html>
""" % (DATE, VERSION, DATE, VERSION, "\n".join(todo_rows), "\n".join(rows))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--outdir", default="docs/planning")
    args = ap.parse_args()

    os.makedirs(args.outdir, exist_ok=True)
    md_path = os.path.join(args.outdir, BASENAME + ".md")
    html_path = os.path.join(args.outdir, BASENAME + ".html")

    with open(md_path, "w", encoding="utf-8") as fh:
        fh.write(build_markdown())
    with open(html_path, "w", encoding="utf-8") as fh:
        fh.write(build_html())

    print("written: %s" % md_path)
    print("written: %s" % html_path)
    todo = [i for i in ITEMS if i[5] == "需补购"]
    print("todo items: %d" % len(todo))
    for item in todo:
        print("  %s %s -> %s" % (item[0], item[2], search_url(item[6])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
