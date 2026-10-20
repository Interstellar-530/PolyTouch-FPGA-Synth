"""Check PDF contents and page bounds; render temporary QA pages."""
from pathlib import Path
import json
import pymupdf

ROOT=Path(__file__).resolve().parents[1]
PDF=ROOT/'output/pdf/FPGA-逐根接线手册-20261018-v0.1.pdf'
EV=ROOT/'docs/evidence/FPGA-接线复核-20261018-v0.1'
QA=ROOT/'tmp/wiring-20261018/pages'


def main():
    QA.mkdir(parents=True,exist_ok=True)
    d=pymupdf.open(PDF)
    text='\n'.join(p.get_text() for p in d)
    assert '\ufffd' not in text, 'Replacement glyphs'
    required=['今天','debug','27MHz','PT8211','250kHz','J5-11','J5-12',
              'J14-10','PCM5102A','D-56-05-08','3.072MHz','48kHz','VREF/2',
              'SCL','XMT','13','600ms']
    for token in required:
        assert token in text, ('missing',token)
    outside=[]
    page_summary=[]
    for i,p in enumerate(d):
        for block in p.get_text('dict')['blocks']:
            for line in block.get('lines',[]):
                for span in line['spans']:
                    x0,y0,x1,y1=span['bbox']
                    if x0<15 or x1>p.rect.width-15 or y0<10 or y1>p.rect.height-10:
                        outside.append({'page':i+1,'text':span['text'],'bbox':span['bbox']})
        page_summary.append({'page':i+1,'chars':len(p.get_text()),
                             'first_lines':p.get_text().splitlines()[2:5]})
        p.get_pixmap(dpi=110).save(QA/f'page-{i+1:02}.png')
    assert not outside,outside
    result={'pages':len(d),'critical_tokens':len(required),'replacement_chars':0,
            'outside_page_bounds':outside,'page_summary':page_summary,
            'visual_review':'pending manual inspection of rendered pages'}
    (EV/'pdf_checks.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({'pages':len(d),'critical_tokens':len(required),'bounds':'PASS'},ensure_ascii=True))


if __name__=='__main__':main()
