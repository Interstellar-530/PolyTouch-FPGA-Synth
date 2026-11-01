"""Reproduce the reviewed wiring checklist, checks and Pandoc/XeLaTeX PDF.

Run from any directory with tools/.venv-docconvert/Scripts/python.exe.
No RTL changes, hardware access, downloads or cleanup are performed here.
"""
from pathlib import Path
import csv
import hashlib
import json
import re
import subprocess
import pypandoc

ROOT = Path(__file__).resolve().parents[1]
DOC = ROOT / 'docs/hardware/FPGA-逐根接线手册-20261018-v0.1.md'
CHECKLIST = DOC.with_name('FPGA-逐根接线核对单-20261018-v0.1.md')
PDF = ROOT / 'docs/exports/pdf/FPGA-逐根接线手册-20261018-v0.1.pdf'
EVIDENCE = ROOT / 'evidence/2026/10/FPGA-接线复核-20261018-v0.1'
SOURCE = ROOT / 'source'

# Connector-to-ball map read from the rendered Dock3714 PDF pages 1/4/9.
HEADERS = {
    'J5': ['L9', 'N8', 'N9', 'N7', 'N6', 'D11', 'A11', 'B11'],
    'J6': ['B12', 'C12', 'B13', 'A14', 'B14', 'A15', 'D14', 'E15'],
    'J14': ['P9', 'T9', 'T8', 'P8', 'R8', 'T7', 'T6', 'P6'],
}


def main():
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    plan = ROOT / 'docs/hardware/FPGA-pinplan-20261013-v0.1.csv'
    rows = list(csv.DictReader(plan.read_text(encoding='utf-8-sig').splitlines()))
    cst_path = SOURCE / 'constraints/primer20k_i2s.cst'
    cst = cst_path.read_text(encoding='utf-8-sig')
    ports = dict(re.findall(r'IO_LOC\s+"([^"]+)"\s+(\w+)\s*;', cst))
    wrapper_path = SOURCE / 'build/isolated/top_std_build.v'
    wrapper = wrapper_path.read_text(encoding='utf-8-sig').split(');', 1)[0]
    checks = []
    debug_cst = (SOURCE/'constraints/primer20k_dock3714.cst').read_text(encoding='utf-8-sig')
    debug_ports = dict(re.findall(r'IO_LOC\s+"([^"]+)"\s+(\w+)\s*;', debug_cst))
    lines = ['# 逐根接线核对单（2026-10-18，v0.1）', '',
             '**今天使用 debug 和板载 27MHz/PT8211：只执行标为今天的行。**', '',
             '后续 standard 行本次不接。方框供现场填写，不表示已经接线或测量通过。', '',
             '**晶振暂无转接 PCB；DAC 已有正面照片，电源路径及焊桥仍待核对；P15W 暂不用。**', '',
             '| 已接 | 复核 | 编号 | 线的一端 | 线的另一端 | 备注 |',
             '|---|---|---|---|---|---|']

    def wire(a, b, note=''):
        count = sum(line.startswith('| [ ]') for line in lines) + 1
        future = any(word in a+b for word in ['晶振','DAC','33Ω']) or a.startswith(('J6-5 /','J6-6 /','J6-7 /','J14-10 /','J14-12 /'))
        note = ('后续 standard，本次不接；' if future else '今天 debug；') + note
        lines.append(f'| [ ] | [ ] | W{count:03} | {a} | {b} | {note} |')

    targets = {
        'adc_cs_n': 'MCP3208 10/CS', 'adc_sck': 'MCP3208 13/CLK',
        'adc_mosi': 'MCP3208 11/DIN', 'adc_miso': 'MCP3208 12/DOUT',
        'i2s_bck': 'DAC BCK', 'i2s_lrck': 'DAC LCK/LRCK',
        'i2s_din': 'DAC DIN', 'dac_xsmt': 'DAC XSMT（先查焊桥）',
        'clk_12m288': '33Ω 电阻靠板端（另一端接晶振 OUT）',
    }
    for row in rows:
        signal = row['signal']
        m = re.fullmatch(r'key(\d+)_n', signal)
        port = f'gpio_key_n[{m[1]}]' if m else signal
        connector, pin = row['connector'].split('-')
        ball = row['fpga_pin']
        assert HEADERS[connector][int(pin)-5] == ball, row
        assert ports[port] == ball, (port, ball)
        base = port.split('[')[0]
        assert re.search(r'\b' + re.escape(base) + r'\b', wrapper), port
        assert re.search(r'IO_PORT\s+"' + re.escape(port) + r'"\s+IO_TYPE=LVCMOS33', cst), port
        expected_bank = '7' if ball in {'D11','A11','B11','B12','C12','B13','A14','B14','A15'} else ('1' if ball in {'D14','E15'} else '3')
        assert row['bank'] == expected_bank, row
        if m:
            assert row['direction'] == 'input'
            target = f'K{m[1]} 信号节点 S'
        else:
            assert row['direction'] == ('input' if port in {'adc_miso','clk_12m288'} else 'output')
            target = targets[signal]
        if m or signal.startswith('adc_'):
            assert debug_ports[port] == ball, ('debug mismatch', port)
        wire(f"{row['connector']} / {ball}", target, f"{row['direction']}，Bank{row['bank']}，3.3V")
        checks.append(dict(port=port, connector=row['connector'], ball=ball,
                           bank=row['bank'], direction=row['direction'], passed=True))
    assert len(rows) == 21 and len({r['connector'] for r in rows}) == 21
    for a,b,n in [
        ('J5-1','面包板 3V3 轨','红线'), ('J5-3','面包板 GND 轨','黑线'),
        ('3V3 轨','MCP3208 16/VDD',''), ('3V3 轨','MCP3208 15/VREF',''),
        ('GND 轨','MCP3208 14/AGND',''), ('MCP3208 14/AGND','MCP3208 9/DGND','就近短接'),
        ('J14-1','晶振 VCC','型号和 3.3V 电压确认后接'),
        ('J14-3','晶振 GND','确认实物脚序后接'),
        ('晶振 OUT','33Ω 电阻源端','确认输出电平，电阻靠近晶振'),
        ('晶振 OE/EN','按完整型号资料使能','NC 不乱接；尚待确认'),
        ('J6-3','DAC GND',''),
        ('已核实的模块电源','DAC 已核实电源输入','VIN/3V3 不预设、不同时接'),
    ]: wire(a,b,n)
    for pin in range(3,9): wire(f'MCP3208 {pin}/CH{pin-1}','ADC AGND','本次未用通道')
    for name,a,b in [('C1 100nF','ADC 16/VDD','ADC 14/AGND'),
                     ('C2 100nF','ADC 15/VREF','ADC 14/AGND'),
                     ('C3 约1µF','ADC 16/VDD','ADC 14/AGND'),
                     ('C4 100nF','晶振 VCC','晶振 GND'),
                     ('C5 约1µF','晶振 VCC','晶振 GND')]:
        wire(name+' 一端',a,'电容并在电源与地间')
        wire(name+' 另一端',b,'有极性时该端为负')
    for a,b,n in [
        ('3V3','FSR-A',''),('FSR-B','节点 F',''),
        ('节点 F','ADC 1/CH0',''),('节点 F','FSR 10kΩ 一端',''),
        ('FSR 10kΩ 另一端','ADC AGND',''),
        ('电位器固定端 A','3V3','先用万用表识别固定端'),
        ('电位器固定端 B','ADC AGND',''),('电位器滑动端 W','ADC 2/CH1','先调到 VREF/2'),
    ]: wire(a,b,n)
    for k in range(12):
        wire(f'K{k} 开关信号侧',f'K{k} 节点 S','与本键底板信号相通')
        wire(f'K{k} 开关地侧','GND','选按下才导通的两组触点')
        wire(f'K{k} 节点 S',f'K{k} 10kΩ 上拉一端','每键独立')
        wire(f'K{k} 10kΩ 上拉另一端','3V3','不能省略')
    for function in ['SCK/MCLK','FMT','DEMP','FLT']:
        wire('DAC '+function,'DAC GND','先核对模块是否已有正确焊桥；不重复改焊')
    for a,b in [('DAC OUTL','有源音箱 LINE IN L'),('DAC OUTR','有源音箱 LINE IN R'),
                ('DAC GND','有源音箱 LINE IN GND')]: wire(a,b,'或接已确认有线输入功放；P15W 输入待确认')
    lines += ['', 'J5-7、J14-6、J14-11 留空；RGB LCD、麦克风 FPC 留空。', '',
              '功放高压电源和喇叭线不列为本轮已批准上电线束：须先确认有线输入、适配器及负载。', '',
              'debug 回退时，断电拔下 J6-5/6/7 与 J14-12 的外部 DAC 线，板载耳机口出声；',
              '该档使用板载 27MHz，FSR 不控制音量。正式路线仍选 standard。', '']
    CHECKLIST.write_text('\n'.join(lines), encoding='utf-8')
    doc = DOC.read_text(encoding='utf-8')
    for row in rows:
        assert row['fpga_pin'] in doc
    metadata = {
        'git_head': subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
        'checked_signal_count':21, 'debug_checked_signal_count':16, 'all_passed':True, 'rows':checks,
        'header_source':'Visual review of Dock3714 PDF pages 1/4/9; image evidence retained',
        'physical_measurements_performed':False, 'rtl_modified':False, 'hardware_programmed':False,
        'pending':['oscillator H.ELE 4F voltage/pinout and adapter PCB',
                   'CJMCU power path and solder bridges','P15W analog input and speaker supply/load'],
        'hashes': {str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest()
                   for p in [DOC,CHECKLIST,plan,cst_path,wrapper_path]},
    }
    (EVIDENCE/'pin_crosscheck.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2),encoding='utf-8')
    layout = EVIDENCE/'wiring-layout.tex'
    layout.write_text(r'''\usepackage{needspace}
\usepackage{fancyhdr}
\usepackage{etoolbox}
\setlength{\emergencystretch}{3em}
\setlength{\tabcolsep}{4pt}
\renewcommand{\arraystretch}{1.07}
\AtBeginEnvironment{longtable}{\small}
\pretocmd{\section}{\Needspace{5\baselineskip}}{}{}
\pretocmd{\subsection}{\Needspace{4\baselineskip}}{}{}
\setlength{\headheight}{15pt}
\pagestyle{fancy}\fancyhf{}
\fancyhead[L]{\small PolyTouch FPGA / 逐根接线手册}
\fancyhead[R]{\small 2026-10-18 / v0.1}
\fancyfoot[C]{\small\thepage}
''',encoding='utf-8')
    PDF.parent.mkdir(parents=True,exist_ok=True)
    pypandoc.convert_file(str(DOC),'pdf',format='markdown+raw_tex',outputfile=str(PDF),extra_args=[
        '--pdf-engine=xelatex','--standalone','--include-in-header='+str(layout),
        '-V','mainfont=Microsoft YaHei','-V','CJKmainfont=Microsoft YaHei',
        '-V','monofont=Consolas','-V','CJKmonofont=Microsoft YaHei',
        '-V','geometry:a4paper,margin=1.7cm','-V','linestretch=1.03'])
    print(json.dumps({'checked_signals':21,'checklist_wires':sum(x.startswith('| [ ]') for x in lines),
                      'pdf':str(PDF)},ensure_ascii=False))


if __name__ == '__main__':
    main()
