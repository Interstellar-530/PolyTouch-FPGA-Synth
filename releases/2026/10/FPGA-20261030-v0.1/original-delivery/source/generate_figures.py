"""Reproducible, dependency-free SVG authoring. Render with render_figures.cjs."""
from pathlib import Path
from html import escape
import json

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'target'
OUT.mkdir(exist_ok=True)

class Figure:
    def __init__(self, name, title, subtitle, dark=False, height=1080):
        self.name, self.h = name, height
        self.c = dict(bg='#101C30', panel='#182940', ink='#F3F7FC', sub='#B4C4D9', line='#425775', teal='#58DFCB', blue='#8DBAFF', amber='#F1C377') if dark else dict(bg='#F8FAFD', panel='#FFFFFF', ink='#152944', sub='#53677E', line='#CED9E5', teal='#007E78', blue='#2864B6', amber='#94600D')
        c=self.c
        self.p=[f'<svg xmlns="http://www.w3.org/2000/svg" width="1920" height="{height}" viewBox="0 0 1920 {height}" role="img" aria-labelledby="title desc"><title id="title">{escape(title)}</title><desc id="desc">{escape(subtitle)}。实线为音频或事件流，虚线为控制与状态。依据当前32声部HDMI生产源码。</desc>', f'<defs><marker id="arrow" markerUnits="userSpaceOnUse" markerWidth="12" markerHeight="12" viewBox="0 0 9 9" refX="8" refY="4.5" orient="auto-start-reverse"><path d="M0 0 L9 4.5 L0 9Z" fill="{c["teal"]}"/></marker><marker id="ctrl" markerUnits="userSpaceOnUse" markerWidth="12" markerHeight="12" viewBox="0 0 9 9" refX="8" refY="4.5" orient="auto"><path d="M0 0 L9 4.5 L0 9Z" fill="{c["blue"]}"/></marker></defs>', f'<rect width="1920" height="{height}" fill="{c["bg"]}"/>', f'<style>text{{font-family:"Microsoft YaHei","Noto Sans CJK SC",sans-serif}} .line{{fill:none;stroke-linejoin:round;stroke-linecap:round}}</style>']
        self.text(64,58,'POLYTOUCH  /  FPGA SYNTHESIZER',19,'teal',600)
        self.text(64,120,title,44,weight=700)
        self.text(64,164,subtitle,23,'sub')
        self.line([(64,194),(1856,194)],'line',width=1,arrow=False)
    def text(self,x,y,t,size=25,color='ink',weight=400,anchor='start'):
        self.p.append(f'<text x="{x}" y="{y}" font-size="{size}" font-weight="{weight}" fill="{self.c[color]}" text-anchor="{anchor}">{escape(t)}</text>')
    def line(self, pts, color='teal', dash=False, width=3, arrow=True):
        d='M'+' L'.join(f'{x} {y}' for x,y in pts)
        self.p.append(f'<path class="line" d="{d}" stroke="{self.c[color]}" stroke-width="{width}"'+(' stroke-dasharray="8 7"' if dash else '')+(f' marker-end="url(#{"ctrl" if color=="blue" else "arrow"})"' if arrow else '')+'/>')
    def box(self,x,y,w,h,title,lines=(),accent='teal',tag=None):
        self.p.append(f'<g data-panel="{escape(title)}"><rect x="{x}" y="{y}" width="{w}" height="{h}" rx="16" fill="{self.c["panel"]}" stroke="{self.c["line"]}"/>')
        self.p.append(f'<rect x="{x+22}" y="{y+24}" width="5" height="28" rx="2" fill="{self.c[accent]}"/>')
        self.text(x+40,y+47,title,27,weight=600)
        for i,t in enumerate(lines): self.text(x+24,y+88+i*34,t,22,'sub')
        if tag: self.text(x+24,y+h-20,tag,18,accent,500)
        self.p.append('</g>')
    def label(self,x,y,t):self.text(x,y,t,21,'sub')
    def footer(self,detail='当前源码快照 · 2026-10-30 · 32 声部 HDMI 路径'):
        y=self.h-62
        self.line([(64,y-25),(1856,y-25)],'line',width=1,arrow=False)
        self.text(64,y+8,detail,18,'sub')
        self.text(1856,y+8,'GW2A-18  ·  纯硬件实时合成',18,'sub',anchor='end')
    def save(self):
        self.p.append('</svg>'); (OUT/(self.name+'.svg')).write_text('\n'.join(self.p),encoding='utf-8')

def overview(dark=False):
    f=Figure('01-overview-'+('dark' if dark else 'light'),'从演奏动作到声音输出','32 声部时分复用波表合成 · 控制、音频与可视化协同运行',dark)
    for x,n,t in [(64,'01','演奏输入'),(514,'02','声部管理'),(964,'03','实时合成'),(1414,'04','声音输出')]:
        f.text(x,249,n,23,'teal',600);f.text(x+48,249,t,27,weight=600)
    f.box(64,284,360,198,'音符与演奏控制',['USB 键盘 / 串口演奏','演示曲：定时音符事件','统一送入声部合成通路'])
    f.box(514,284,360,198,'32 声部调度',['事件仲裁、队列与延音','分配 / 重触发 / 释音','ADSR 包络与弯音参数'])
    f.box(964,284,360,198,'共享波表流水线',['相位累加 → ROM 查表','位置插值 + 音色阶段插值','包络 × 力度 → 多声部累加'])
    f.box(1414,284,442,198,'主混音 → I2S → DAC',['音色混合、音量与饱和保护','24 位 / 46.875 kHz','PCM5102A → 模拟音频输出'])
    for a,b in [(424,514),(874,964),(1324,1414)]:f.line([(a,383),(b-10,383)])
    f.box(64,588,360,238,'表情输入与稳定检测',['FSR → 三点中值 → 回差','按下 2 点 / 松开 6 点','稳定踏板 → 手动延音','旋钮 → 实时弯音比例'],accent='blue',tag='2 kHz · 状态更新目标小于 5 ms')
    f.line([(244,588),(244,534),(694,534),(694,494)],'blue',True)
    f.label(395,524,'延音 / 弯音控制')
    f.box(514,588,810,178,'演示曲构建：保存演奏信息',['曲谱转写与多声部编排 → 编译按键、松键、力度及等待指令','事件存入 BSRAM ROM → 板上按节拍派发 → 同一合成引擎'],tag='曲目 ROM 存演奏指令；音色波表 ROM 存单周期波形')
    f.box(1414,588,442,178,'HDMI 实时显示',['音频波形 / 32 格声部活动','音符与力度统计 → 频带活动'],accent='blue',tag='显示通过快照同步，音频走独立 DAC')
    f.line([(1635,482),(1635,575)],'blue',True)
    f.line([(874,430),(914,430),(914,557),(1380,557),(1380,675),(1402,675)],'blue',True)
    f.text(64,852,'算法要点',23,'teal',600)
    f.text(64,898,'演示曲相当于一份自动弹奏记录：规定何时弹什么音、力度多大、何时松开。',29,weight=500)
    f.text(64,944,'FPGA 逐声部、逐样本合成声音后输出 I2S；曲目存储不含整曲 PCM、WAV 或 MP3。',22,'sub')
    f.footer();f.save()

def detail():
    f=Figure('02-signal-flow-detail','信号处理与合成算法详解','当前生产源码 · 32 声部 / 54 MHz 计算域 / 46.875 kHz 采样率',height=1960)
    f.text(64,242,'A  演奏事件与控制参数',25,'teal',600)
    f.box(64,272,336,184,'统一演奏事件输入',['手动：CH9350L / 串口','自动：曲目 ROM 定时派发','Note On / Off + 力度'])
    f.box(464,272,398,184,'事件整理与延音',['仲裁 → 同音来源管理 → FIFO','踏板按下：暂存 Note Off','确认松开：补发 → ADSR 释音'])
    f.box(926,272,420,184,'跨域握手 → 声部调度',['事件与控制：27 → 54 MHz','同音重触发 → 空闲 → 抢占','ADSR、音高步进 × 弯音比例'])
    f.box(1410,272,446,184,'参数更新 → 声部状态 RAM',['音区 / 力度选表，高音增益修正','按变更声部提交配置事务','保存相位、步进、包络与选表'])
    for a,b in [(400,464),(862,926),(1346,1410)]: f.line([(a,362),(b-10,362)])
    f.text(64,526,'B  每个采样帧依次遍历 32 个声部',25,'teal',600)
    f.line([(1633,456),(1633,545),(210,545),(210,558)])
    f.box(64,570,294,198,'读声部状态',['相位、步进、包络','力度、波表与权重','φ ← φ + Δφ'])
    f.box(410,570,320,198,'共享 BSRAM 查表',['512 点 / 16 位波表','正弦 + 乐器波表','读取相邻位置与相邻表'])
    f.box(782,570,322,198,'两级线性插值',['位置：相邻采样点插值','音色：相邻表权重插值','钢琴阶段间平滑过渡'])
    f.box(1156,570,320,198,'包络与力度缩放',['插值结果 × ADSR','再乘演奏力度','保留 24 位声部样本'])
    f.box(1528,570,328,198,'双路 32 位累加',['正弦声部求和','乐器声部求和','完成后提交主混音'])
    for a,b in [(358,410),(730,782),(1104,1156),(1476,1528)]:f.line([(a,668),(b-8,668)])
    f.line([(1692,768),(1692,807),(211,807),(211,780)],'blue',True)
    f.label(570,838,'声部状态回写相位；下一声部复用同一 ROM 与运算流水线')
    f.text(64,907,'C  帧级主混音、输出与显示',25,'teal',600)
    f.box(64,942,382,202,'主混音与输出整形',['正弦 / 乐器混合权重渐变','32 声部归一化 → 主音量','平滑静音 → 24 位饱和保护'],tag='复用合成流水线空闲期乘法器')
    f.box(510,942,382,202,'音频帧跨域桥',['完成样本：54 → 27 MHz','帧请求与结果握手同步','对齐 I2S 采样节拍'])
    f.box(956,942,404,202,'标准 I2S → PCM5102A',['24 位有效数据 / 32 位声道槽','LRCK 46.875 kHz / BCK 3 MHz','左右同样本 → DAC 模拟输出'])
    f.box(1424,942,432,202,'状态与音频快照 → HDMI',['输出样本 → 波形 / 点阵','声部 mask → 32 格活动窗','音符与力度 → 8 频带活动'],accent='blue',tag='频带活动为统计值，未执行 FFT')
    f.line([(1810,768),(1810,920),(255,920),(255,930)])
    for a,b in [(446,510),(892,956)]:f.line([(a,1038),(b-10,1038)])
    f.line([(701,1144),(701,1184),(1640,1184),(1640,1156)],'blue',True)
    f.text(64,1232,'时序预算：54,000,000 ÷ 46,875 = 1152 拍/帧；声部遍历主体 19 × 32 = 608 拍。',23,'sub')
    f.text(64,1269,'其余时隙用于配置提交与主混音；具体吞吐和余量以完整 RTL 仿真及实现时序报告为准。',21,'sub')
    f.box(64,1320,860,188,'曲目事件 ROM → 本图 A 区输入',['曲谱与编排 → Note On / Off、力度、等待、循环','song_player32 按采样节拍解码，FIFO 就绪后交付事件'],tag='只描述演奏动作和时序，不向 I2S 提供预录音频样本')
    f.box(956,1320,900,188,'音色波表 ROM → 本图 B 区查表',['512 点单周期波形按相位寻址、插值，再经 ADSR 与混音','手动演奏与自动演奏使用相同的板上逐样本合成通路'],tag='波表描述音色；演示曲事件表描述曲谱，二者职责不同')
    f.text(64,1560,'D  延音踏板稳定算法：控制路径生成稳定踏板状态，送入 A 区延音逻辑',25,'teal',600)
    f.box(64,1600,382,228,'压力采集与快速判定',['MCP3208 CH0，2 kHz 更新','三点中值去除孤立尖峰','踏板判定不经过显示用 IIR'],tag='快速开关与平滑显示分开处理')
    f.box(510,1600,382,228,'回差与连续样本确认',['未踩：连续 2 点 ≥512 才按下','已踩：连续 6 点 ≤256 才松开','条件中断清计数；仅新样本推进'],tag='名义确认：约 1 ms / 3 ms')
    f.box(956,1600,404,228,'保护已保持的音符',['IdleOnly 空闲超时保留延音','明确断开 / Panic 仍紧急清音','严格策略超时仍执行清音'],tag='区分键盘空闲与真正断开')
    f.box(1424,1600,432,228,'确认松开后有序释音',['暂存 Note Off，松踏板后补发','仍被按住的键保留；支持背压','同音重触发取消旧的待释音'],tag='新 Note On 通过原事件通路')
    for a,b in [(446,510),(892,956),(1360,1424)]:f.line([(a,1715),(b-10,1715)],'blue',True)
    f.text(64,1862,'确认窗口不等于全链路延迟；≤10 ms 要求须包含采集、滤波、事件调度和实际音频输出进行验证。',21,'sub')
    f.footer();f.save()

def demo():
    f=Figure('03-demo-construction','演示曲如何构建与发声','曲目保存类似自动弹奏的事件信息；声音仍由 FPGA 实时合成',height=1380)
    f.text(64,245,'A  开发期：从曲谱编排到事件 ROM',25,'teal',600)
    f.box(64,280,382,218,'曲谱转写与编排',['记录音高、起始拍、时值、力度','保留旋律与和声，编排伴奏','整理同音来源与按下 / 松开'],tag='song_data.py / song_kuanggu.py')
    f.box(510,280,382,218,'编译演奏事件序列',['按时间排序，生成按下 / 松开','时间间隔编码为等待单位','曲末加入循环标记'],tag='gen_arrangement32.py')
    f.box(956,280,404,218,'初始化曲目 BSRAM ROM',['16 位指令，3 个 pROM 块','两首曲目连续存放，按基址选曲','保存音符事件及时间间隔'],tag='arrangement32_rom.v')
    f.box(1424,280,432,218,'曲目存储的实际含义',['保存何时弹、音高与演奏力度','记录松开与等待，描述演奏时序','最终声音在开发板上实时生成'],accent='blue',tag='类似自动弹奏记录，不是完整音频')
    for a,b in [(446,510),(892,956)]:f.line([(a,390),(b-10,390)])
    f.text(64,602,'B  板上运行：事件驱动同一套实时合成引擎',25,'teal',600)
    f.box(64,640,382,218,'硬件曲目时序器',['读取事件 ROM，解码与等待','按采样节拍计时，支持变速','就绪握手后派发 Note On / Off'],tag='song_player32.v')
    f.box(510,640,382,218,'统一事件通路与声部调度',['手动键盘 / 串口也送入此处','队列 → 跨域 → 分配与释音','每声部保留相位与包络状态'],tag='32 个声部复用运算流水线')
    f.box(956,640,404,218,'FPGA 逐样本实时计算',['相位 → 单周期音色波表查表','插值 → ADSR × 力度 → 混音','音高、音色与音量参与运算'],tag='音色波表独立于曲目事件 ROM')
    f.box(1424,640,432,218,'板上生成音频并输出',['主混音 → 24 位样本','标准 I2S → PCM5102A DAC','46.875 kHz，左右相同样本'],tag='此处才产生最终音频样本')
    f.line([(1158,498),(1158,566),(44,566),(44,750),(52,750)])
    for a,b in [(446,510),(892,956),(1360,1424)]:f.line([(a,750),(b-10,750)])
    f.text(64,930,'16 位曲目指令实例',25,'teal',600)
    f.box(64,960,568,178,'0xBC70：按下音符',['Note On，音高 60（C4），力度 112','编码：0x8000 | (60 << 8) | 112'])
    f.box(676,960,568,178,'0x0004：等待',['等待 4 个十六分音符单位','每单位由采样节拍与速度参数决定'])
    f.box(1288,960,568,178,'0x3C00：松开音符',['Note Off，音高 60，进入释音','0x0000 为回到本曲起点的标记'])
    f.text(64,1200,'曲目 ROM 记录“何时弹、弹什么、用多大力度、何时松开”，不是完整音频文件。',27,weight=600)
    f.text(64,1245,'波表仅提供周期波形；整曲声音由开发板在运行时逐声部、逐样本计算生成。',24,'sub')
    f.footer();f.save()

def pedal():
    f=Figure('04-sustain-stability','延音踏板稳定检测与释音流程','纯 HDL 控制路径 · 2 kHz 新样本更新 · 按下 2 点 / 松开 6 点',height=1620)
    f.text(64,244,'A  从压力到稳定踏板状态',25,'teal',600)
    f.box(64,280,382,198,'采集压力',['FSR → MCP3208 CH0','12 位 ADC，每组采样完成更新','更新频率 2 kHz，间隔 0.5 ms'])
    f.box(510,280,382,198,'快速中值判定路径',['取当前与前两点的中值 m','三点中值后直接进入判定','显示用 IIR 保留在独立支路'])
    f.box(956,280,404,198,'状态相关的回差判定',['未按下：检查 m ≥ 512','已按下：检查 m ≤ 256','中间区域维持既有踏板状态'])
    f.box(1424,280,432,198,'连续确认生成稳定状态',['按下连续 2 点，松开连续 6 点','条件不成立就清对应计数','无 update 不推进；复位清状态'])
    for a,b in [(446,510),(892,956),(1360,1424)]:f.line([(a,380),(b-10,380)],'blue',True)
    f.text(64,548,'B  两个状态分别计数，短时低谷恢复后重新开始松开确认',25,'teal',600)
    f.box(64,585,860,246,'未按下：确认踩下踏板',['m ≥ 512：累积按下计数；不足 2 点仍未按下','连续第 2 点满足条件：踏板状态置 1，清按下计数','m < 512：按下计数清零，等待新的连续高值'],accent='blue',tag='三点中值 + 按下确认；计数不受 IIR 收敛速度影响')
    f.box(956,585,900,246,'已按下：确认松开踏板',['m ≤ 256：累积松开计数；不足 6 点仍保持延音','连续第 6 点满足条件：踏板状态置 0，清松开计数','m > 256：松开计数清零，不累加不连续低谷'],accent='blue',tag='三点中值 + 松开确认；测试 2 ms 掉压保持场景')
    f.text(64,908,'C  稳定踏板状态决定 Note Off 的处理，音频仍逐样本合成',25,'teal',600)
    f.box(64,945,568,230,'踏板按住时',['Note On 正常发送，记录按键仍被按住','Note Off 暂存，保持声部 gate','同音重新按下时取消旧待释音'],tag='手动模式启用；演示曲保留自身事件时序')
    f.box(676,945,568,230,'踏板确认松开后',['扫描暂存的 Note Off，按就绪握手补发','仍被按住的音符继续保留','声部进入 ADSR Release，生成自然余音'],tag='背压时等待下游，不丢弃释音事件')
    f.box(1288,945,568,230,'保持延音与紧急清音',['IdleOnly 键盘空闲超时保留音乐状态','明确断开 / Panic / 复位仍可清音','严格策略超时按原规则清音'],accent='blue',tag='空闲超时不再误当成设备断开')
    f.line([(632,1058),(666,1058)],'blue',True)
    f.text(64,1254,'确认窗口：按下约 1 ms / 松开约 3 ms；中值与采样对齐另计，稳定阶跃状态更新预算 ≤4 ms。',25,weight=600)
    f.text(64,1303,'赛题基础要求：至少两个独立演奏维度、纯 HDL 实时合成、控制到音频输出总延迟 ≤10 ms。',23,'sub')
    f.text(64,1344,'小于 5 ms 的状态更新时间按持续跨阈值阶跃验证；完整音频响应仍需计入 ADC、调度及 DAC。',23,'sub')
    f.text(64,1385,'踏板用于延音控制；旋钮控制弯音。演示曲仅存演奏事件，全部声音由开发板实时合成。',23,'sub')
    f.text(64,1460,'稳定性边界：2 ms 短掉压可保持；持续 5 ms 的低值按松开处理。ADSR 自然余音不等于状态延迟。',21,'sub')
    f.footer();f.save()

overview(False);overview(True);detail();demo();pedal()
print(json.dumps({'figures':sorted(p.name for p in OUT.glob('*.svg'))},ensure_ascii=False))
