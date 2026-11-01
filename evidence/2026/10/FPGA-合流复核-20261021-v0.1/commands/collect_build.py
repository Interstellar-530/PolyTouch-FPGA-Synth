"""Collect current debug8usb reports and content hashes without programming hardware."""
from pathlib import Path
import hashlib
import json
import re
import shutil

ROOT = next(p for p in Path(__file__).resolve().parents if (p / '.git').exists())
OUT = Path(__file__).resolve().parents[1]


def main():
    receipt_path = ROOT / 'output/handoff_milestone2_20261008/source/build/receipts/debug8usb.json'
    receipt = json.loads(receipt_path.read_text(encoding='utf-8-sig'))
    pnr = Path(receipt['Bitstream']).parent
    reports = OUT / 'build_reports'
    reports.mkdir(exist_ok=True)
    for name in ['instrument.rpt.txt', 'instrument_tr_content.html', 'instrument_tr_cata.html',
                 'instrument.tr.html', 'instrument.pin.html']:
        shutil.copy2(pnr / name, reports / name)
    shutil.copy2(receipt_path, OUT / 'debug8usb.receipt.json')
    timing = (pnr / 'instrument_tr_content.html').read_text()
    report = (pnr / 'instrument.rpt.txt').read_text()

    def cells(anchor):
        section = timing.split('name="' + anchor + '"', 1)[1].split('</table>', 1)[0]
        return [[re.sub('<[^>]*>', '', value).strip()
                 for value in re.findall(r'<t[dh][^>]*>(.*?)</t[dh]>', row, re.S)]
                for row in re.findall(r'<tr>(.*?)</tr>', section, re.S)]

    def resource(name):
        row = re.search(r'^\s*' + re.escape(name) + r'\s*\|\s*([\d.]+)(?:/(\d+))?', report, re.M)
        if not row:
            raise ValueError('missing resource ' + name)
        return float(row[1]), int(row[2]) if row[2] else None

    inputs = {}
    for row in receipt['Inputs']:
        path = Path(row['Path'])
        inputs[path.relative_to(ROOT).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
    result = dict(profile='debug8usb', part='GW2A-LV18PG256C8/I7', device_version='C',
                  logic=resource('Logic')[0], logic_available=resource('Logic')[1],
                  registers=resource('Register')[0], bsram=resource('BSRAM')[0],
                  bsram_available=resource('BSRAM')[1], dsp_units=resource('DSP')[0],
                  mult18x18=resource('--MULT18X18')[0], mult9x9=resource('--MULT9X9')[0],
                  multalu36x18=resource('--MULTALU36X18')[0], clock_mhz=27.0,
                  fmax=cells('Max_Frequency_Report'), tns=cells('Total_Negative_Slack_Report'),
                  worst_setup=cells('Setup_Slack_Table')[1], worst_hold=cells('Hold_Slack_Table')[1],
                  bitstream=receipt['Bitstream'],
                  bitstream_sha256=hashlib.sha256(Path(receipt['Bitstream']).read_bytes()).hexdigest(),
                  inputs_sha256=inputs, hardware_programmed=False,
                  build_exit=int((OUT / 'debug8usb_build.exit.txt').read_text()))
    (OUT / 'build_metrics.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({k: result[k] for k in ('logic', 'registers', 'bsram', 'dsp_units', 'worst_setup', 'worst_hold')}))


if __name__ == '__main__':
    main()
