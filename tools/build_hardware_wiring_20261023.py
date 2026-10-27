"""Generate precise vector wiring figures and build the Markdown-first manual.

Figures: bundled Python + reportlab. Crops/build/QA: project docconvert Python.
Run with --figures using bundled runtime, then --build/--qa in docconvert venv.
"""
import argparse
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MD = ROOT / 'docs/hardware/FPGA-现有硬件图解接线方案-20261023-v0.1.md'
ASSETS = MD.parent / 'wiring-20261023-v0.1-assets'
OUTPUT = ROOT / 'output/pdf/FPGA-现有硬件图解接线方案-20261023-v0.1.pdf'
TMP = ROOT / 'tmp/hardware-wiring-20261023'


def figures():
    from reportlab.pdfgen import canvas
    from reportlab.pdfbase import pdfmetrics
    from reportlab.pdfbase.ttfonts import TTFont
    from reportlab.lib.colors import HexColor
    from reportlab.lib.units import mm
    pdfmetrics.registerFont(TTFont('CN', r'C:\Windows\Fonts\msyh.ttc'))
    pdfmetrics.registerFont(TTFont('CNB', r'C:\Windows\Fonts\msyhbd.ttc'))
    ASSETS.mkdir(parents=True, exist_ok=True)
    blue, red, green, orange, grey = '#164B73', '#BD3434', '#247A58', '#B26A00', '#64748B'

    class Figure:
        def __init__(self, name, h):
            self.h = h
            self.c = canvas.Canvas(str(ASSETS / name), pagesize=(170*mm, h*mm))
            self.c.setTitle(name)

        def text(self, x, y, text, size=8, color=blue, bold=False, align='left'):
            c = self.c
            c.setFillColor(HexColor(color)); c.setFont('CNB' if bold else 'CN', size)
            for i, line in enumerate(text.split('\n')):
                yy = (self.h-y-i*size*0.43)*mm
                method = {'left': c.drawString, 'center': c.drawCentredString, 'right': c.drawRightString}[align]
                method(x*mm, yy, line)

        def line(self, x1, y1, x2, y2, color=blue, dash=False, width=1):
            c = self.c; c.setStrokeColor(HexColor(color)); c.setLineWidth(width)
            c.setDash(3, 2) if dash else c.setDash()
            c.line(x1*mm, (self.h-y1)*mm, x2*mm, (self.h-y2)*mm)
            c.setDash()

        def box(self, x, y, w, h, title='', body='', fill='#EFF6FA', size=8):
            c = self.c; c.setFillColor(HexColor(fill)); c.setStrokeColor(HexColor('#ADC2D0'))
            c.setLineWidth(.7)
            c.roundRect(x*mm, (self.h-y-h)*mm, w*mm, h*mm, 2*mm, stroke=1, fill=1)
            if title: self.text(x+w/2, y+6, title, 9, bold=True, align='center')
            if body: self.text(x+w/2, y+12, body, size, align='center')

        def arrow(self, x1, y1, x2, y2, label='', color=blue):
            self.line(x1,y1,x2,y2,color)
            import math
            theta=math.atan2(y2-y1,x2-x1)
            for a in (-.45,.45):
                self.line(x2,y2,x2-2*math.cos(theta+a),y2-2*math.sin(theta+a),color)
            if label:self.text((x1+x2)/2,(y1+y2)/2-2,label,6.8,color,align='center')

        def dot(self,x,y,color=blue,r=1):
            c=self.c;c.setFillColor(HexColor(color));c.circle(x*mm,(self.h-y)*mm,r*mm,stroke=0,fill=1)

        def save(self):self.c.showPage();self.c.save()

    f=Figure('01-system.pdf',91)
    f.box(0,9,43,22,'普通 USB 键盘','接 CH9350L Host 口')
    f.box(0,42,43,23,'CH9350L 下位机','115200 / 8N1\nTXD=3.3V，VBUS=5V',size=7)
    f.arrow(21,31,21,42,'USB')
    f.box(62,32,46,33,'Tang Primer 20K','standard27 / 8声部\n板载27MHz\n48kHz档暂不混用',size=7.5)
    f.arrow(43,52,62,52,'W01 UART')
    f.box(126,33,44,30,'PCM5102A','BCK / LCK / DIN\n24bit / 46.875kHz',size=7.5)
    f.arrow(108,47,126,47,'I2S')
    f.box(63,4,45,18,'到货晶振','先独立测量；T7留空',fill='#F3F4F6',size=7)
    f.box(0,73,43,17,'FSR＋电位器','压力CH0 / 弯音CH1',size=7)
    f.box(63,73,45,17,'MCP3208','SPI，3.3V参考',size=7)
    f.arrow(43,81,63,81,'模拟')
    f.arrow(85,73,85,65,'SPI')
    f.box(126,73,44,17,'音箱暂不可用','测I2S；模拟端按仪器验收',fill='#FFF6E8',size=6.5)
    f.arrow(148,63,148,73,'LINE OUT',green)
    f.save()

    f=Figure('04-headers.pdf',91)
    labels=[('PMOD3 / 照片右下',[(0,'A11/DIN',0,'B11/DOUT'),(0,'N6/CS',0,'D11/CLK'),(0,'N9/空',0,'N7/空'),(0,'L9/RX',0,'N8/空'),(0,'GND',0,'GND'),(0,'3V3',0,'3V3')]),
            ('PMOD2 / 照片中下',[(0,'D14/空',0,'E15/空'),(0,'B14/空',0,'A15/空'),(0,'B13/DIN',0,'A14/空'),(0,'B12/BCK',0,'C12/LCK'),(0,'GND',0,'GND'),(0,'3V3',0,'3V3')]),
            ('PMOD0 / 照片右上',[(0,'T6/空',0,'P6/空'),(0,'R8/空',0,'T7/空'),(0,'T8/空',0,'P8/空'),(0,'P9/空',0,'T9/空'),(0,'GND',0,'GND'),(0,'3V3',0,'3V3')])]
    for col,(name,rows) in enumerate(labels):
        x=col*57;f.box(x,2,55,85,name,'按你的板背照片朝向',size=6.5)
        for r,(n1,l1,n2,l2) in enumerate(rows):
            y=25+r*10
            for n,label,dx in [(n1,l1,2),(n2,l2,29)]:
                color=red if label=='3V3' else grey if '空' in label else green if label=='GND' else blue
                f.dot(x+dx+2,y,color,1.25)
                f.text(x+dx+4.5,y+.9,label,6.5,color)
    f.save()

    f=Figure('05-power.pdf',75)
    f.box(0,5,51,25,'Dock 已知供电入口','先USB-JTAG单独供电\n暂不并接J13',size=7.5)
    f.box(66,5,46,25,'3V3 小信号支路','PMOD3 / 3V3 → ADC / FSR\nPMOD3 / GND → 公共地',size=6.5)
    f.arrow(51,17,66,17,'3V3',red)
    f.box(0,47,51,22,'独立外设供电','仅在入口额定值确认后接入',fill='#FFF6E8',size=7)
    f.box(66,47,46,22,'CH9350L','Host VBUS必须5V\nTXD必须3.3V',fill='#FFF6E8',size=7)
    f.arrow(51,58,66,58,'核对',orange)
    f.box(126,5,44,25,'DAC供电入口待核','VCC与3.3V孔只选一路\n先查LDO和焊桥',fill='#FFF6E8',size=6.8)
    f.box(126,47,44,22,'公共地 GND','Dock / ADC / DAC / 键盘\n只共地，正极不硬并联',size=6.6)
    f.line(89,30,89,38,green);f.line(89,38,148,38,green);f.line(148,38,148,47,green)
    f.text(3,40,'3V3、5V、12V分轨贴标签；任何5V/12V都不进入FPGA信号脚。',7,red)
    f.save()

    f=Figure('06-adc.pdf',102)
    f.box(61,11,48,79,'MCP3208','SOIC-16 顶视图',size=7)
    f.text(85,8,'缺口 / 1脚圆点朝上',7,align='center')
    left=['CH0 → A01 / FSR','CH1 → A02 / 旋钮','CH2 → AGND','CH3 → AGND','CH4 → AGND','CH5 → AGND','CH6 → AGND','CH7 → AGND']
    right=['VDD → 3V3','VREF → 3V3','AGND → GND','CLK ← W04 / D11','DOUT → W06 / B11','DIN ← W05 / A11','CS ← W03 / N6','DGND → GND']
    for i in range(8):
        y=30+i*7.7
        f.line(56,y,61,y);f.text(63,y+1,str(i+1),7)
        f.text(54,y+1,left[i],7,align='right')
        f.line(109,y,114,y);f.text(107,y+1,str(16-i),7,align='right')
        f.text(116,y+1,right[i],7)
    f.text(1,99,'16脚→100nF＋约1µF→地；15脚→100nF→地。电容并联，14/9脚就近短接。',7,green)
    f.save()

    f=Figure('07-sensors.pdf',77)
    f.text(3,7,'FSR 压力 → CH0',9,bold=True)
    f.text(99,7,'10kΩ 电位器 → CH1',9,bold=True)
    f.text(18,17,'3V3',8,red);f.line(24,19,24,24,red)
    f.box(14,24,20,12,'FSR402',size=7);f.line(24,36,24,42);f.dot(24,42)
    f.line(24,42,65,42);f.text(40,38,'A01 → ADC 1 / CH0',7)
    f.line(24,42,24,48);f.box(16,48,16,12,'10kΩ',size=7)
    f.line(24,60,24,66,green);f.text(24,72,'AGND',8,green,align='center')
    f.text(121,17,'3V3',8,red);f.line(127,19,127,26,red)
    f.box(120,26,14,31,'10kΩ','固定端\n到固定端',size=6)
    f.line(127,57,127,66,green);f.text(127,72,'AGND',8,green,align='center')
    f.arrow(153,42,134,42);f.text(145,36,'滑臂',7,align='center')
    f.text(148,51,'A02 → ADC 2',7,align='center');f.text(148,56,'CH1',7,align='center')
    f.save()

    f=Figure('08-dac.pdf',108)
    f.box(42,3,56,101,'CJMCU-5102 正面','LINE OUT插座在上方',size=7)
    f.box(61,17,30,10,'LINE OUT',fill='#E4E8EB')
    names=['VCC','3.3V','GND','FLT','DMP','SCL','BCK','DIN','LCK','FMT','XMT']
    targets=['供电入口待核','可能为稳压输出','P03 / PMOD2 GND','固定低','固定低','固定低：不是BCK','W07 / PMOD2 B12','W09 / PMOD2 B13','W08 / PMOD2 C12','固定低：I2S','固定3.3V；P6留空']
    for i,(name,target) in enumerate(zip(names,targets)):
        y=20+i*7.5
        color=red if i<2 else green if i==2 else blue
        f.dot(46,y,color);f.text(49,y+1,name,7,color)
        f.line(39,y,46,y,color);f.text(37,y+1,str(i+1),6,grey,align='right')
        f.line(98,y,106,y,color);f.text(109,y+1,target,7,color)
    f.text(3,105,'左侧1至11仅为本图孔位序号，不能当作PCM5102A芯片脚号。',7,red)
    f.save()

    f=Figure('09-i2s.pdf',72)
    f.box(0,4,49,32,'Dock PMOD2','B12 → BCK\nC12 → LCK\nB13 → DIN',size=8)
    f.box(121,4,49,32,'DAC 模块','BCK\nLCK\nDIN',size=8)
    for i,label in enumerate(['W07','W08','W09']):
        y=16+i*6;f.arrow(49,y,121,y,label)
    f.line(49,42,121,42,green);f.text(85,48,'PMOD2 / GND',7,green,align='center')
    f.box(0,54,79,17,'逻辑分析仪','高阻监听BCK / LRCK / DIN＋GND',size=7)
    f.box(91,54,79,17,'示波器或真实Line In','接DAC L/R与音频GND；不直接插耳机',fill='#FFF6E8',size=7)
    f.save()

    f=Figure('10-keyboard.pdf',75)
    f.box(0,5,50,27,'USB 键盘','插模块Host口\n不插FPGA排针',size=8)
    f.box(65,5,50,27,'CH9350L','下位机 / state 2\n115200 / 8N1',size=8)
    f.arrow(50,18,65,18,'USB')
    f.box(133,5,37,27,'Dock PMOD3','L9\n键盘UART RX',size=7)
    f.arrow(115,18,133,18,'TXD',blue)
    f.text(118,35,'W01：3.3V TTL',7)
    f.box(65,47,50,23,'模块 RXD → 模块 GND','W02，单向传输',fill='#EAF5EE',size=7)
    f.line(90,32,90,47,green)
    f.box(133,47,37,23,'PMOD3 / N8','留空，不接地\n不接模块RXD',fill='#FFF2EE',size=7)
    f.text(2,50,'Host VBUS：5V\n模块供电口按实物确认\n所有信号设备共地',7,orange)
    f.save()

    f=Figure('11-oscillator.pdf',84)
    f.text(3,7,'底视图：引脚朝向眼睛',8,bold=True)
    f.box(3,14,48,42)
    for x,y,n,label in [(11,24,1,'NC/使能'),(43,24,4,'GND'),(11,47,8,'VCC'),(43,47,5,'OUT')]:
        f.dot(x,y,blue,1.5);f.text(x,y-3,str(n),8,align='center')
        f.text(x,y+6,label,6,align='center')
    f.text(59,7,'顶视图：定位圆点在左下',8,bold=True)
    f.box(59,14,48,42)
    for x,y,n,label in [(67,24,8,'VCC'),(99,24,5,'OUT'),(67,47,1,'定位点/NC'),(99,47,4,'GND')]:
        f.dot(x,y,blue,1.5);f.text(x,y-3,str(n),8,align='center');f.text(x,y+6,label,6,align='center')
    f.text(116,19,'8脚 → 3.3V\n4脚 → GND\n5脚 → 独立测频/幅度\n1脚 → NC或使能待核\n8-4脚并100nF',7)
    f.text(115,52,'standard27：T7不接',7.5,red,bold=True)
    f.text(3,68,'后续确认12.288MHz与匹配板级档：5脚OUT → 约33Ω → PMOD0 / T7',7)
    f.text(3,77,'翻面按定位点重新认脚；不能将四根脚重编号为1、2、3、4。',7,red)
    f.save()
    # Keep original user photos intact; PDF vector overlays identify regions.
    from reportlab.lib.utils import ImageReader
    photo=ASSETS/'user-dock-back.jpg'
    if photo.exists():
        f=Figure('12-board-photo.pdf',143)
        f.c.drawImage(ImageReader(str(photo)),0,(143-7-133.333)*mm,width=100*mm,height=133.333*mm)
        for y,h,title,body in [
            (34.8,15,'PMOD0（照片右上）','T7：本轮不接晶振\nP6：本轮不接DAC静音\nT9：板载RGB LED共用'),
            (78,17,'PMOD2（照片右侧）','B12 → DAC BCK\nC12 → DAC LCK\nB13 → DAC DIN\nGND → DAC GND'),
            (103,17,'PMOD3（照片右下）','L9 ← CH9350L TXD\nN8：留空\nN6/D11 → ADC CS/CLK\nA11/B11 → ADC DIN/DOUT')]:
            f.c.setStrokeColor(HexColor(red));f.c.setLineWidth(1.2)
            f.c.rect(64*mm,(143-y-h)*mm,15*mm,h*mm,stroke=1,fill=0)
            f.arrow(79,y+h/2,105,y+h/2,color=red)
            f.text(106,y+1,title,7.5,bold=True)
            f.text(106,y+6,body,6.5)
        f.text(3,5,'你的Dock背面照片；按此朝向读丝印，插正面时重新确认同针。',7,bold=True)
        f.save()

    photo=ASSETS/'user-dac-front.jpg'
    if photo.exists():
        f=Figure('13-dac-photo.pdf',88)
        f.c.drawImage(ImageReader(str(photo)),0,0,width=66*mm,height=88*mm)
        f.text(77,9,'按用户实物照片读左侧孔名',9,bold=True)
        f.text(77,20,'LINE OUT插座在照片上方\n\nVCC / 3.3V：先核供电网络\nGND → PMOD2 GND\nBCK ← PMOD2 B12\nDIN ← PMOD2 B13\nLCK ← PMOD2 C12\nFMT / SCL / DMP / FLT 固定低\nXMT固定3.3V，P6留空',8)
        f.text(77,80,'模块孔名不是芯片脚号。',8,red)
        f.save()
    print('Vector figures:', ASSETS)


def crops():
    import pymupdf as fitz
    ASSETS.mkdir(parents=True, exist_ok=True)
    doc=fitz.open(ROOT/'docs/references/Tang_Primer_20K_Dock_3714_Schematics.pdf')
    for name,page,rect,highlight in [
        ('02-dock-j5j6.pdf',3,(.425,.21,.64,.48),[(.518,.25,.562,.322),(.518,.385,.562,.46)]),
        ('03-dock-j14.pdf',8,(.76,.295,.95,.42),[(.845,.327,.877,.407)])]:
        p=doc[page];w,h=p.rect.width,p.rect.height
        clip=fitz.Rect(rect[0]*w,rect[1]*h,rect[2]*w,rect[3]*h)
        out=fitz.open();np=out.new_page(width=clip.width,height=clip.height)
        np.show_pdf_page(np.rect,doc,page,clip=clip)
        for r in highlight:
            hr=fitz.Rect(r[0]*w-clip.x0,r[1]*h-clip.y0,r[2]*w-clip.x0,r[3]*h-clip.y0)
            np.draw_rect(hr,color=(.9,.2,.15),width=1.2)
        out.save(ASSETS/name)
    # Extra source evidence is useful for checking exact package pin positions.
    for src,page,rect,name in [
        ('MCP3208_Microchip_DS21298E.pdf',0,(.54,.69,.91,.85),'source-mcp-pins.pdf'),
        ('PCM5102A_TI_SLAS859C.pdf',4,(.34,.12,.64,.38),'source-pcm-pins.pdf')]:
        d=fitz.open(ROOT/'docs/references'/src);p=d[page];w,h=p.rect.width,p.rect.height
        clip=fitz.Rect(rect[0]*w,rect[1]*h,rect[2]*w,rect[3]*h)
        out=fitz.open();np=out.new_page(width=clip.width,height=clip.height);np.show_pdf_page(np.rect,d,page,clip=clip)
        out.save(ASSETS/name)
    for f in ASSETS.glob('*.pdf'):
        d=fitz.open(f);d[0].get_pixmap(matrix=fitz.Matrix(2,2)).save(TMP/(f.stem+'.png'))
    print('Crops and figure previews ready')


def build():
    import os
    import pypandoc
    TMP.mkdir(parents=True, exist_ok=True);OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    os.chdir(MD.parent)
    # raw TeX provides deliberate page boundaries and vector schematic panels.
    tex = pypandoc.convert_file(str(MD),'latex',format='markdown',extra_args=[
        '--standalone','-V','mainfont=Microsoft YaHei','-V','CJKmainfont=Microsoft YaHei',
        '-V','monofont=Consolas','--resource-path='+str(MD.parent)])
    # Bundled Pandoc emits a graphics alt key newer than installed TeX Live.
    # Preserve visible figure captions, strip only that unsupported optional key.
    tex = re.sub(r',alt=\{[^{}]*\}', '', tex).replace('\r\n','\n').replace('\r','\n')
    texfile = TMP/'manual.tex';texfile.write_text(tex,encoding='utf-8',newline='\n')
    for _ in range(2):
        r = subprocess.run(['xelatex','-interaction=nonstopmode','-halt-on-error',
             '-output-directory='+str(TMP),str(texfile)],cwd=MD.parent,capture_output=True)
        (TMP/'build.log').write_bytes(r.stdout+r.stderr)
        if r.returncode:raise RuntimeError(r.stdout.decode(errors='replace')[-4500:])
    import shutil
    shutil.copyfile(TMP/'manual.pdf',OUTPUT)
    print(OUTPUT)


def qa():
    import pymupdf as fitz
    from PIL import Image,ImageOps,ImageDraw
    TMP.mkdir(parents=True,exist_ok=True)
    d=fitz.open(OUTPUT);summary=[];thumbs=[]
    for i,p in enumerate(d):
        path=TMP/f'page-{i+1:02}.png';p.get_pixmap(matrix=fitz.Matrix(1.5,1.5)).save(path)
        txt=p.get_text();outside=[]
        for word in p.get_text('words'):
            r=fitz.Rect(word[:4])
            if not p.rect.contains(r):outside.append(word[4])
        summary.append({'page':i+1,'chars':len(txt),'replacement_chars':txt.count('\ufffd'),
                        'outside_bounds':outside,'headings':re.findall(r'\d\d\s*[|｜][^\n]+',txt)})
        im=Image.open(path).convert('RGB');im.thumbnail((297,420))
        thumb=Image.new('RGB',(317,450),'#DDE4EA');thumb.paste(im,((317-im.width)//2,10))
        ImageDraw.Draw(thumb).text((10,432),str(i+1),fill='black');thumbs.append(thumb)
    for start in range(0,len(thumbs),6):
        sheet=Image.new('RGB',(317*3,450*2),'#DDE4EA')
        for j,im in enumerate(thumbs[start:start+6]):sheet.paste(im,((j%3)*317,(j//3)*450))
        sheet.save(TMP/f'contact-{start//6+1}.jpg',quality=90)
    full=''.join(p.get_text() for p in d)
    compact=re.sub(r'\s+','',full)
    required=['PMOD3','PMOD2','PMOD0','L9','N6','D11','A11','B11','B12','C12','B13','T7','P6',
              'BCK','LCK','DIN','XMT','115200','46.875','3.000','2048','4095','IdleOnly']
    missing=[s for s in required if s not in compact]
    cst=ROOT/'output/handoff_milestone2_20261008/source/constraints/primer20k_i2s_27m.cst'
    text=cst.read_text(encoding='utf-8-sig')
    mapping={'kbd_uart_rx':'L9','kbd_uart_tx':'N8','adc_cs_n':'N6','adc_sck':'D11',
             'adc_mosi':'A11','adc_miso':'B11','i2s_bck':'B12','i2s_lrck':'C12','i2s_din':'B13','dac_xsmt':'P6'}
    for port,ball in mapping.items():
        assert re.search(r'IO_LOC\s+"'+port+r'"\s+'+ball+r';',text),(port,ball)
    result={'pages':len(d),'page_checks':summary,'critical_tokens_missing':missing,
            'cst_mapping':mapping,'passed':not missing and all(not x['outside_bounds'] and x['replacement_chars']==0 for x in summary)}
    assert result['passed'],result
    (TMP/'qa.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(result,ensure_ascii=False,indent=2))


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--figures',action='store_true');p.add_argument('--crops',action='store_true');p.add_argument('--build',action='store_true');p.add_argument('--qa',action='store_true');a=p.parse_args()
    if a.figures:figures()
    if a.crops:crops()
    if a.build:build()
    if a.qa:qa()
