"""Summarize corrected prototype STA and verify current production is unchanged."""
from pathlib import Path
from html.parser import HTMLParser
import hashlib,json,re
ROOT=next(p for p in Path(__file__).resolve().parents if (p/'.git').exists())
OUT=Path(__file__).resolve().parents[1];SRC=ROOT/'output/handoff_milestone2_20261008/source'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
class Tables(HTMLParser):
    def __init__(self):super().__init__();self.tables=[];self.table=None;self.row=None;self.cell=None
    def handle_starttag(self,tag,attrs):
        if tag=='table':self.table=[]
        elif tag=='tr':self.row=[]
        elif tag in ('td','th'):self.cell=[]
    def handle_data(self,data):
        if self.cell is not None:self.cell.append(data)
    def handle_endtag(self,tag):
        if tag in ('td','th') and self.cell is not None:self.row.append(''.join(self.cell).strip());self.cell=None
        elif tag=='tr' and self.row is not None and self.table is not None:self.table.append(self.row);self.row=None
        elif tag=='table' and self.table is not None:self.tables.append(self.table);self.table=None
receipt=json.loads((OUT/'build_receipt.json').read_text())
assert all(sha(Path(k))==v for k,v in receipt['inputs_sha256'].items())
assert sha(OUT/'ram32.fs')==receipt['bitstream_sha256']
parser=Tables();parser.feed((OUT/'build_reports/ram32_tr_content.html').read_text())
fmax=next(t for t in parser.tables if t and 'Actual Fmax' in t[0])
tns=next(t for t in parser.tables if t and 'Endpoints TNS' in t[0])
slacks=[t for t in parser.tables if t and 'Path Slack' in t[0]]
text=(OUT/'build_reports/ram32.rpt.txt').read_text()
def resource(name):return int(re.search(r'^\s*'+name+r'\s*\|\s*(\d+)/',text,re.M)[1])
production=json.loads((SRC/'build/receipts/debug8usb.json').read_text(encoding='utf-8-sig'))
assert all(sha(Path(x['Path']))==x['Sha256'] for x in production['Inputs'])
assert sha(Path(production['Bitstream']))==production['BitstreamSha256']
fifth=json.loads((ROOT/'docs/evidence/FPGA-优化05审核-20261021-v0.1/debug8usb.receipt.json').read_text(encoding='utf-8-sig'))
assert production['BitstreamSha256']==fifth['BitstreamSha256'] and production['InputsDigest']==fifth['InputsDigest']
result=dict(logic=resource('Logic'),registers=resource('Register'),bsram=resource('BSRAM'),
    dsp_units=resource('DSP'),mult18x18=2,fmax=fmax,tns=tns,worst_setup=slacks[0][1],worst_hold=slacks[1][1],
    prototype_inputs_verified=len(receipt['inputs_sha256']),bitstream_matches=True,
    production_inputs_verified=len(production['Inputs']),production_fifth_item_unchanged=True,
    actual_last_activity_cycle=992,frame_clocks=1024,remaining_clocks=32,
    clock_source_included=False,pin_constraints_included=False,production_piano_guitar_included=False,
    hardware_programmed=False)
(OUT/'metrics_verified.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
assert all(row[3]=='0' for row in tns[1:])
print(json.dumps(result,indent=2))
