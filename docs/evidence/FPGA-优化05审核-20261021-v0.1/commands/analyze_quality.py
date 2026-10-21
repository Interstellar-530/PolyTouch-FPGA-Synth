"""Independent read-only audit against the pre-item-5 archive. Requires numpy."""
from pathlib import Path
import csv,hashlib,json,re,wave
import numpy as np
ROOT=next(p for p in Path(__file__).resolve().parents if (p/'.git').exists())
OUT=Path(__file__).resolve().parents[1]
AUDIO=ROOT/'output/handoff_milestone2_20261008/source/rtl/audio'
OLD=ROOT/'archive/FPGA-20261021-v0.6/source/rtl/audio'
IMPL=ROOT/'docs/evidence/FPGA-优化05-波表复用-20261021'
def load(p):
    return np.array([int(v,16) for v in p.read_text(encoding='ascii').split()],dtype=np.uint16).view(np.int16).astype(np.int64).reshape(-1,512)
def db(ratio):return float(20*np.log10(max(float(ratio),1e-30)))
def rms(a):return float(np.sqrt(np.mean(np.asarray(a,dtype=float)**2)))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
rows=[];summary={}
for kind,file in [('piano','epiano_bank_all.hex'),('guitar','guitar_bank_all.hex')]:
    old=load(OLD/file);new=load(AUDIO/file)
    saved=load(IMPL/'banks_before'/file.replace('.hex','_36.hex'))
    assert np.array_equal(old,saved), 'Supplied baseline differs from fourth-item archive'
    mapping=[z if kind=='piano' and z==5 else 0 if kind=='piano' else max(z-1,0) for z in range(6)]
    if kind=='piano':mapping=[0,0,0,0,0,1]
    remapped=np.concatenate([new[g*6:g*6+6] for g in mapping])
    assert remapped.shape==old.shape
    for bank,(a,b) in enumerate(zip(old,remapped)):
        d=b-a;af=np.fft.rfft(a);bf=np.fft.rfft(b)
        primary=np.abs(af)>np.max(np.abs(af[1:]))*1e-3;primary[0]=False
        gain=db(np.dot(a,b)/np.dot(a,a))
        delta_db=np.abs(20*np.log10(np.abs(bf[primary])/np.abs(af[primary])))
        phase=np.abs(np.angle(bf[primary]/af[primary]))*180/np.pi
        row=dict(kind=kind,bank=bank,zone_or_band=bank//6,stage_or_variant=bank%6,
                 equal=bool(np.array_equal(a,b)),error_rms_db_re_signal=db(rms(d)/rms(a)),
                 error_rms_lsb=rms(d),error_peak_lsb=int(np.max(np.abs(d))),
                 dc_change_lsb=float(np.mean(d)),gain_change_db=gain,
                 primary_harmonic_max_magnitude_change_db=float(np.max(delta_db)),
                 primary_harmonic_max_phase_change_deg=float(np.max(phase)))
        # Exhaust all 512 addresses x 512 interpolation fractions at production F=2.
        frac=np.arange(512,dtype=np.int64)[None,:]
        def interp(t):return (t[:,None]<<2)+((((np.roll(t,-1)-t)[:,None]*frac)<<2)+256)//512
        delta=interp(b)-interp(a)
        row['interpolated_max_error_lsb']=float(np.max(np.abs(delta)))/4
        rows.append(row)
    own=[r for r in rows if r['kind']==kind]
    summary[kind]=dict(old_tables=len(old),new_tables=len(new),baseline_archive_matches=True,
        logical_tables_equal=sum(x['equal'] for x in own),logical_tables=len(own),
        worst_table=max(own,key=lambda r:r['error_rms_db_re_signal']),
        max_peak_lsb=max(x['error_peak_lsb'] for x in own),
        max_interpolated_peak_lsb=max(x['interpolated_max_error_lsb'] for x in own),
        max_primary_harmonic_change_db=max(x['primary_harmonic_max_magnitude_change_db'] for x in own),
        max_primary_harmonic_phase_change_deg=max(x['primary_harmonic_max_phase_change_deg'] for x in own),
        max_abs_gain_change_db=max(abs(x['gain_change_db']) for x in own))
    if kind=='guitar':assert np.array_equal(old,remapped)
    else:
        assert np.array_equal(old[:6],new[:6]) and np.array_equal(old[30:],new[6:])
        # Frequency-domain upper-band energy across the supported table range.
        alias=[]
        for note in range(96):
            hz=440*2**((note-69)/12);inc=round(hz/46875*2**32)
            z=next((i for i,x in enumerate([0x400000,0x800000,0x1000000,0x2000000,0x4000000]) if inc<x),5)
            if z==5:continue # retained bit-for-bit, no compaction error
            h=np.arange(257);mask=h*hz>=46875/2
            for stage in range(6):
                a=np.fft.rfft(old[z*6+stage]);b=np.fft.rfft(remapped[z*6+stage])
                energy=np.sum(np.abs((b-a)[mask])**2)/np.sum(np.abs(a[1:])**2)
                alias.append(float(10*np.log10(max(energy,1e-30))))
        summary[kind]['worst_above_nyquist_difference_energy_db']=max(alias)
    # Independently unpack every pROM INIT word, not just the bank HEX.
    rom=AUDIO/('gowin_prom_piano_bank.v' if kind=='piano' else 'gowin_prom_guitar_bank.v')
    packed=re.findall(r"\.INIT_RAM_[0-9A-F]{2}\(256'h([0-9A-Fa-f]+)\)",rom.read_text())
    values=[(int(chunk,16)>>(16*i))&0xffff for chunk in packed for i in range(16)]
    assert np.array_equal(np.array(values,dtype=np.uint16).view(np.int16).astype(np.int64),new.ravel())
    summary[kind]['prom_words_verified']=len(values)
    def wav(p):
        with wave.open(str(p),'rb') as w:
            assert w.getsampwidth()==2 and w.getnchannels()==1
            return np.frombuffer(w.readframes(w.getnframes()),dtype='<i2').astype(np.int64),w.getframerate()
    b,fs=wav(IMPL/'audio'/kind/'before.wav');a,fs2=wav(IMPL/'audio'/kind/'after.wav')
    assert fs==fs2 and len(a)==len(b)
    d=a-b
    summary[kind]['existing_wav']=dict(fs=fs,samples=len(a),error_rms_db_re_signal=db(rms(d)/rms(b)),
        error_rms_dbfs=db(rms(d)/32768),error_peak_dbfs=db(np.max(np.abs(d))/32768),
        error_rms_lsb=rms(d),error_peak_lsb=int(np.max(np.abs(d))),exact_equal=bool(np.array_equal(a,b)))
    b,fs=wav(OUT/'audio'/kind/'before.wav');a,fs2=wav(OUT/'audio'/kind/'after.wav')
    assert fs==fs2 and len(a)==len(b)
    d=a-b
    summary[kind]['review_model_wav']=dict(fs=fs,samples=len(a),error_rms_db_re_signal=db(rms(d)/rms(b)),
        error_rms_dbfs=db(rms(d)/32768),error_peak_dbfs=db(np.max(np.abs(d))/32768),
        error_rms_lsb=rms(d),error_peak_lsb=int(np.max(np.abs(d))),exact_equal=bool(np.array_equal(a,b)))

paired=[]
with (OUT/'rtl_pairs.csv').open() as handle:
    paired=list(csv.DictReader(handle))
rtl=[]
for kind in [0,1,2]:
    cases=sorted({(int(r['note']),int(r['velocity']),int(r['tone'])) for r in paired if int(r['kind'])==kind})
    cases_result=[]
    for note,vel,tone in cases:
        case=[r for r in paired if tuple(int(r[x]) for x in ['kind','note','velocity','tone'])==(kind,note,vel,tone)]
        a=np.array([int(r['old']) for r in case]);b=np.array([int(r['new']) for r in case]);d=b-a
        cases_result.append(dict(note=note,velocity=vel,tone=tone,samples=len(a),
            max_error_q2_units=int(np.max(np.abs(d))),rms_db_re_signal=db(rms(d)/max(rms(a),1e-30))))
    rtl.append(dict(kind=kind,cases=len(cases),frames=sum(x['samples'] for x in cases_result),
        max_error_q2_units=max(x['max_error_q2_units'] for x in cases_result),
        worst_case=max(cases_result,key=lambda x:x['rms_db_re_signal'])))
result=dict(summary=summary,tables=rows,rtl_summary=rtl,inputs_sha256={str(p.relative_to(ROOT)):sha(p) for p in
    [OLD/'epiano_bank_all.hex',OLD/'guitar_bank_all.hex',AUDIO/'epiano_bank_all.hex',AUDIO/'guitar_bank_all.hex']},
    hearing_test=False,full_rtl_render=False)
(OUT/'quality_analysis.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps(summary,ensure_ascii=False,indent=2))
print(json.dumps(rtl,ensure_ascii=False,indent=2))
