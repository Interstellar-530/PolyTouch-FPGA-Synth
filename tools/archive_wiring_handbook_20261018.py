"""Archive this documentation delivery without changing RTL or hardware."""
from pathlib import Path
from PIL import Image, ImageOps, ImageDraw
import hashlib
import json
import shutil

ROOT=Path(__file__).resolve().parents[1]
EV=ROOT/'docs/evidence/FPGA-接线复核-20261018-v0.1'
DEST=ROOT/'archive/FPGA-20261018-v0.1'


def main():
    assert not DEST.exists(), 'Archive already exists; do not overwrite'
    # All final pages have been inspected; retain a small contact sheet as QA evidence.
    page_count=json.loads((EV/'pdf_checks.json').read_text(encoding='utf-8'))['pages']
    pages=[ROOT/f'tmp/wiring-20261018/pages/page-{i:02}.png' for i in range(1,page_count+1)]
    assert len(pages)==12 and all(p.is_file() for p in pages)
    sheet=Image.new('RGB',(1200,4*570),'#dddddd')
    for i,path in enumerate(pages):
        im=Image.open(path).convert('RGB')
        im=ImageOps.contain(im,(390,550))
        x=(i%3)*400+(400-im.width)//2;y=(i//3)*570
        sheet.paste(im,(x,y))
        ImageDraw.Draw(sheet).text(((i%3)*400+180,y+550),f'Page {i+1}',fill='black')
    sheet.save(EV/'pdf-contact-sheet.jpg',quality=87)
    p=EV/'pdf_checks.json'; qa=json.loads(p.read_text(encoding='utf-8'))
    qa['visual_review']='PASS: all pages reviewed; revised pages 9/12 reviewed after final change; no clipped tables or orphan continuation page'
    p.write_text(json.dumps(qa,ensure_ascii=False,indent=2),encoding='utf-8')
    sources=['docs/hardware/FPGA-逐根接线手册-20261018-v0.1.md',
             'docs/hardware/FPGA-逐根接线核对单-20261018-v0.1.md',
             'docs/hardware/FPGA-pinplan-20261013-v0.1.csv',
             'tools/build_wiring_handbook_20261018.py',
             'tools/verify_wiring_handbook_20261018.py',
             'tools/archive_wiring_handbook_20261018.py',
             'docs/reviews/FPGA-阶段优化量化总结-20261017-v0.1.md']
    prefix='output/handoff_milestone2_20261008/source/'
    sources += [prefix+name for name in ['constraints/primer20k_i2s.cst',
                'constraints/primer20k_dock3714.cst','build/isolated/top_std_build.v',
                'build/isolated/top_dbg_build.v','rtl/top.v','rtl/audio/gpio_keyboard.v',
                'rtl/audio/pressure_bend.v','rtl/audio/mcp3208_spi.v',
                'rtl/audio/instrument_controls.v','rtl/audio/uart_ctrl.v']]
    for rel in sources:
        out=DEST/'source'/rel;out.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(ROOT/rel,out)
    out=DEST/'deliverables';out.mkdir()
    shutil.copy2(ROOT/'output/pdf/FPGA-逐根接线手册-20261018-v0.1.pdf',out)
    shutil.copy2(ROOT/sources[1],out)
    evidence_text='''# 接线复核证据

基线 ff2c7d6；未修改 RTL，未连接仪器，未烧录。标准档21路及调试档16路与当前约束对应。
PDF 12页，17项关键内容检查、文本边界检查通过；已逐页视觉检查。
源图已按项目流程先转换为Markdown，再检查保留的PNG。
用户最终确认有DAC；正面照片确认为PCM5102A、左列十一孔。D-56-05-08属于所述DAC标注。
今天使用板载27MHz与PT8211的debug接线；压力仅验证采样，默认不调音量。
未确认项为晶振完整参数/转接PCB、DAC电源/背面焊桥、P15W模拟输入与实际负载。
所有检查均为图纸、源码、照片和文档检查，不代表物理电压/连通/音频验收。
'''
    (EV/'README.md').write_text(evidence_text,encoding='utf-8')
    shutil.copytree(EV,DEST/'evidence')
    manuals=['docs/references/Tang_Primer_20K_Dock_3714_Schematics.pdf',
             'docs/references/Tang_Primer_20K_SOM-3961_Schematic.pdf',
             'docs/references/PCM5102A_TI_SLAS859C.pdf',
             'docs/references/MCP3208_Microchip_DS21298E.pdf']
    refs=['# 外部输入记录','', '完整厂商手册保留在原工作区，本归档保留关键页渲染与校验。','']
    refs += [f'- {r}: SHA256 {hashlib.sha256((ROOT/r).read_bytes()).hexdigest()}' for r in manuals]
    (DEST/'source/SOURCE_INPUTS.md').write_text('\n'.join(refs)+'\n',encoding='utf-8')
    (DEST/'REPRODUCE.md').write_text('''# 复现

在原工作区 E:/Working Space/FPGA 中执行，依赖现有 docconvert Python、Pandoc、XeLaTeX、微软雅黑、Pillow、PyMuPDF。
运行依赖在 tools/.venv-docconvert 和本机工具环境中，不属于临时目录；本次没有安装依赖。

```powershell
& 'tools/.venv-docconvert/Scripts/python.exe' 'tools/build_wiring_handbook_20261018.py'
& 'tools/.venv-docconvert/Scripts/python.exe' 'tools/verify_wiring_handbook_20261018.py'
```

构建会从引脚计划、两套CST与封装核对21/16路并生成手册PDF及逐线核对单。
验证会在 tmp/wiring-20261018/pages 产生一次性PNG，人工检查后才可认定排版通过。
归档source保留用于文档复现/审查的输入快照，不是完整可烧录的RTL发布包。
硬件烧录另按手册门禁执行，本归档脚本不访问JTAG。
''',encoding='utf-8')
    (DEST/'CHANGELOG.md').write_text('''# 变更说明

新增12页逐根接线手册、112项端点核对单、实物DAC孔位、原理图渲染和机器检查。
依据用户确认的四脚贴片晶振暂无转接PCB，今天先采用既有debug/板载27MHz/PT8211路线。
保留标准I2S后续接线；纠正旧文档的压力/位深边界和P15W有线输入假定。
既有RTL、配置、旧文档及固件保持原样。回退为移除本轮新增文件，不涉及硬件状态。
任务临时文件仅位于 tmp/wiring-20261018，归档校验后列出并清理。
''',encoding='utf-8')
    files=sorted(p for p in DEST.rglob('*') if p.is_file())
    manifest=['# MANIFEST','', '交付状态：接线文档已核查；实物接线/测量/烧录未执行。','',
              'source 为文档和代码依据快照，deliverables 为目标产物，evidence 为关键证据。','',
              '| 文件 | 字节 |','|---|---|']
    manifest += [f'| {p.relative_to(DEST).as_posix()} | {p.stat().st_size} |' for p in files]
    (DEST/'MANIFEST.md').write_text('\n'.join(manifest)+'\n',encoding='utf-8')
    files=sorted(p for p in DEST.rglob('*') if p.is_file())
    records=[(hashlib.sha256(p.read_bytes()).hexdigest(),p.relative_to(DEST).as_posix()) for p in files]
    (DEST/'checksums.sha256').write_text('\n'.join(h+'  '+p for h,p in records)+'\n',encoding='utf-8')
    assert all(hashlib.sha256((DEST/p).read_bytes()).hexdigest()==h for h,p in records)
    print(json.dumps({'archive':str(DEST),'verified_hashes':len(records)},ensure_ascii=True))


if __name__=='__main__':main()
