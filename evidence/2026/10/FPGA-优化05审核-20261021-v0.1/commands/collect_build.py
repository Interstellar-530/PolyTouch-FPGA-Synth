"""Verify the existing fifth-item build; do not run another synthesis."""
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
implementation=ROOT/'docs/evidence/FPGA-优化05-波表复用-20261021'
before=json.loads((ROOT/'docs/evidence/FPGA-优化04-仲裁路径-20261021/metrics_after.json').read_text(encoding='utf-8-sig'))
after=json.loads((implementation/'metrics_after.json').read_text(encoding='utf-8-sig'))
old={k.lower():v for k,v in before['inputs_sha256'].items()}
new={k.lower():v for k,v in after['inputs_sha256'].items()}
changed=[k for k in old.keys()|new.keys() if old.get(k)!=new.get(k)]
expected={'shared_wavetable_engine.v','gowin_prom_piano_bank.v','gowin_prom_guitar_bank.v',
          'epiano_bank_all.hex','guitar_bank_all.hex','epiano_bank_meta.json','guitar_bank_meta.json'}
assert all(Path(k).parent==SOURCE/'rtl/audio' and (Path(k).name in expected or
           re.fullmatch(r'wave_(epiano_[zg]\d+s\d+|guitar_[bg]\d+v\d+)\.hex',Path(k).name)) for k in changed),changed
assert all(new[x['Path'].lower()]==x['Sha256'] for x in inputs)
assert after['bitstream_sha256']==metrics['bitstream_sha256']
baseline_fs=Path(before['bitstream'])
assert sha(baseline_fs)==before['bitstream_sha256']
metrics['baseline_inputs_changed']=changed
metrics['baseline_bitstream_matches']=True
metrics['implementation_inputs_and_bitstream_match']=True
(OUT/'metrics_verified.json').write_text(json.dumps(metrics,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
assert not bad and metrics['inputs_digest_matches'] and metrics['bitstream_matches'] and metrics['tool_matches']
print(json.dumps(metrics,ensure_ascii=False,indent=2))
