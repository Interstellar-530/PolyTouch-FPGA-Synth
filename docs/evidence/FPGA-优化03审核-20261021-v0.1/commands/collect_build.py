"""Collect the one post-fix build and verify its receipt, using only stdlib."""
from pathlib import Path
from html.parser import HTMLParser
import hashlib, json, re, shutil

ROOT=next(p for p in Path(__file__).resolve().parents if (p/'.git').exists())
OUT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'output/handoff_milestone2_20261008/source'
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()

class Tables(HTMLParser):
    def __init__(self):
        super().__init__();self.tables=[];self.table=None;self.row=None;self.cell=None
    def handle_starttag(self,tag,attrs):
        if tag=='table': self.table=[]
        elif tag=='tr': self.row=[]
        elif tag in ('td','th'): self.cell=[]
    def handle_data(self,data):
        if self.cell is not None: self.cell.append(data)
    def handle_endtag(self,tag):
        if tag in ('td','th') and self.cell is not None:
            self.row.append(''.join(self.cell).strip());self.cell=None
        elif tag=='tr' and self.row is not None and self.table is not None:
            self.table.append(self.row);self.row=None
        elif tag=='table' and self.table is not None:
            self.tables.append(self.table);self.table=None

receipt_path=SOURCE/'build/receipts/debug8usb.json'
receipt=json.loads(receipt_path.read_text(encoding='utf-8-sig'))
fs=Path(receipt['Bitstream']);pnr=fs.parent
reports=OUT/'build_reports';reports.mkdir(exist_ok=True)
for name in ['instrument.rpt.txt','instrument_tr_content.html','instrument.pin.html']:
    shutil.copy2(pnr/name,reports/name)
shutil.copy2(receipt_path,OUT/'debug8usb.receipt.json')
text=(pnr/'instrument.rpt.txt').read_text(encoding='utf-8',errors='replace')
parser=Tables();parser.feed((pnr/'instrument_tr_content.html').read_text(encoding='utf-8',errors='replace'))
fmax=next(t for t in parser.tables if t and 'Actual Fmax' in t[0])
tns=next(t for t in parser.tables if t and 'Endpoints TNS' in t[0])
slacks=[t for t in parser.tables if t and 'Path Slack' in t[0]]
def resource(label):
    m=re.search(r'^\s*'+re.escape(label)+r'\s*\|\s*(\d+(?:\.\d+)?)/(\d+)',text,re.M)
    return float(m[1]) if '.' in m[1] else int(m[1])
inputs=receipt['Inputs']
bad=[x['Path'] for x in inputs if sha(Path(x['Path']))!=x['Sha256'] or Path(x['Path']).stat().st_size!=x['Length']]
# The receipt already uses PowerShell culture ordering; Python ordinal ordering
# would put punctuation in a different order and produce an unrelated digest.
lines=[x['Path'].lower()+'|'+x['Sha256'] for x in inputs]
digest=hashlib.sha256('\n'.join(lines).encode()).hexdigest()
tool=re.search(r'<Tool Version>:\s*(.+)',text)[1].strip()
metrics=dict(profile='debug8usb',logic=resource('Logic'),registers=resource('Register'),
             bsram=resource('BSRAM'),dsp_units=resource('DSP'),fmax=fmax,tns=tns,
             worst_setup=slacks[0][1],worst_hold=slacks[1][1],bitstream=str(fs),
             bitstream_sha256=sha(fs),inputs_checked=len(inputs),input_mismatches=bad,
             inputs_digest_matches=(digest==receipt['InputsDigest']),
             bitstream_matches=(sha(fs)==receipt['BitstreamSha256']),
             tool_matches=(tool==receipt['Tool']['Version']),hardware_programmed=False)
(OUT/'metrics_after_fix.json').write_text(json.dumps(metrics,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
assert not bad and metrics['inputs_digest_matches'] and metrics['bitstream_matches'] and metrics['tool_matches']
print(json.dumps(metrics,ensure_ascii=False,indent=2))
