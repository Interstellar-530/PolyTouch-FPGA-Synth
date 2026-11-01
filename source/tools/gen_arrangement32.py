"""Original-harmony arrangement for the RAM32 engine and its table preview.

Keep the transcribed lead and functional harmony. Pentatonic ornaments live
inside that harmony, rather than sounding an entire scale simultaneously.
"""
from pathlib import Path
import json, math, wave, re, itertools
import numpy as np
import song_data as first
import song_kuanggu as second

ROOT = Path(__file__).resolve().parents[1]

def compile_parts(parts,total):
    changes={}
    for i,p in enumerate(parts):
        changes.setdefault(p['unit'],[]).append((1,i))
        changes.setdefault(p['unit']+p['length'],[]).append((0,i))
    owners={};events=[];peak=0
    def selected():return {n:max(ids,key=lambda i:(parts[i]['part']=='lead',parts[i]['velocity'],-i)) for n,ids in owners.items() if ids}
    for t,actions in sorted(changes.items()):
        before=selected();attacks=set()
        for on,i in sorted(actions):
            n=parts[i]['note']
            if on:owners.setdefault(n,set()).add(i);attacks.add(i)
            else:owners[n].remove(i)
        after=selected();offs=[];ons=[];peak=max(peak,len(after))
        for n in sorted(set(before)|set(after)):
            a=before.get(n);b=after.get(n)
            if a==b and b not in attacks:continue
            if a is not None:offs.append((t,n<<8))
            if b is not None:ons.append((t,0x8000|(n<<8)|parts[b]['velocity']))
        events+=offs+ons
    assert not selected() and peak<=32
    words=[];cursor=0
    for t,w in events:
        if t>cursor:words.append(t-cursor);cursor=t
        words.append(w)
    if cursor<total:words.append(total-cursor)
    words.append(0)
    return words,events,peak

def arrange(which):
    total=first.total_slot_units() if which==0 else second.TOTAL_UNITS
    lead=[];harmony=[];pos=0
    if which==0:
        for n,l,c in first.melody_events():
            if n:lead.append((pos,n,l))
            pos+=l
        pos=0
        for root,q,l in first.chord_events('A'):
            harmony.append((pos,l,first.triad(root,q)));pos+=l
    else:
        lead=sorted((b*16+u,n,l) for b,u,n,l in second.MELODY+[x for g in second.LEGATO for x in g])
        harmony=[(b*16,16,c) for b,c in second.chord_events()]
    key=0 if which==0 else 8
    parts=[]
    def add(t,n,l,v,part):
        if l<=0 or t>=total:return
        assert 24<=n<=88
        parts.append(dict(unit=t,note=n,length=min(l,total-t),velocity=v,part=part))
    for t,n,l in lead:
        add(t,n,l,112,'lead')
        if l>=3:add(t,n-12,l,30,'lead octave')
    previous=(53,57,60)
    for h,(t,length,chord) in enumerate(harmony):
        root,third,fifth=chord
        full=(t>=total//2) or which==1
        # Smooth three-part inner harmony instead of a repeated all-octave pad.
        options=[[n+o for o in (-12,0,12) if 48<=n+o<=72] for n in chord]
        voicings=[tuple(sorted(v)) for v in itertools.product(*options) if len(set(v))==3]
        voicing=min(voicings,key=lambda v:sum(abs(a-b) for a,b in zip(v,previous))+max(0,v[-1]-67)*2)
        previous=voicing
        for v,n in enumerate(voicing):add(t,n,length,22-v*2,'inner harmony')
        if full:
            # Soft upper strings reinforce the chord, with staggered entrances.
            for j,n in enumerate(chord):
                upper=n+12
                if upper<=79:add(t+1+j,upper,max(1,length-2-j),12,'upper harmony')
        for offset,degree in ((0,0),(6,7),(8,0),(14,7)):
            if offset<length:add(t+offset,root-12+degree,min(4,length-offset),42 if offset%8==0 else 28,'bass rhythm')
        if t%16==0:add(t,root-24,min(8,length),16,'sub bass')
        pool=sorted({n+o for n in chord for o in (-12,0,12) if 48<=n+o<=72 and (n-key)%12 in (0,2,4,7,9)})
        pattern=(0,2,1,3,2,1,3,0)
        for j,offset in enumerate(range(0,length,2)):
            add(t+offset,pool[pattern[j%8]%len(pool)],3,18 if j%2==0 else 16,'pentatonic arp left')
        # Interlocking 3+3+2 motion; separate register and a lower dynamic.
        upper=sorted({n+o for n in chord for o in (0,12) if 60<=n+o<=79 and (n-key)%12 in (0,2,4,7,9)})
        if upper and full:
            for j,offset in enumerate(range(1,length,3)):
                add(t+offset,upper[(j+h)%len(upper)],min(4,length-offset),14,'pentatonic arp right')
        for offset in (3,7,11,15):
            if offset<length:add(t+offset,root-5,1,24,'fifth ostinato')
    # A secondary line moves only underneath sustained lead notes, in consonant
    # thirds/sixths/fifths. It does not double each fast melody articulation.
    for t,n,l in lead:
        if l>=4:
            candidates=[m for m in range(55,75) if (m-key)%12 in (0,2,4,7,9) and n-m in (4,7,9,12,16)]
            if candidates:add(t+2,min(candidates,key=lambda m:abs(m-64)),l-1,20,'pentatonic counterline')
    for bar in range(total//16):
        for u in (8,10,12,14):
            t=bar*16+u
            if t+2>total or any(s<t+2 and s+l>t for s,n,l in lead):continue
            past=[n for s,n,l in lead if s<t]
            if past:
                n=past[-1]-12
                if (n-key)%12 in (0,2,4,7,9):add(t,n,2,26,'pentatonic answer')
    # Remove only newly added, close semitone clashes next to a held lead.
    # The transcribed lead and its original functional harmony stay untouched.
    parts=[p for p in parts if p['part'] in ('lead','inner harmony','bass rhythm','sub bass','lead octave') or not any(
        s<p['unit']+p['length'] and s+l>p['unit'] and 0<abs(n-p['note'])<=13 and abs(n-p['note'])%12 in (1,11)
        for s,n,l in lead)]
    words,events,peak=compile_parts(parts,total)
    assert [(p['unit'],p['note'],p['length']) for p in parts if p['part']=='lead']==lead
    assert all((p['note']-key)%12 in (0,2,4,7,9) for p in parts if p['part'].startswith('pentatonic'))
    return words,dict(song=which,bpm=81 if which==0 else 100,units=total,notes=parts,events=events,
                      peak_gated_notes=peak,lead_attacks=len(lead),parts=sorted({p['part'] for p in parts}))

def generate(out):
    a,sa=arrange(0); b,sb=arrange(1); words=a+b
    pages=(len(words)+1023)//1024
    assert pages<=8
    h=[f'localparam [12:0] SECOND_BASE = 13\'d{len(a)};']
    (ROOT/'rtl/audio/arrangement32_layout.vh').write_text('\n'.join(h)+'\n')
    v=['// Generated by tools/gen_arrangement32.py. Event-only BSRAM ROM.',
       'module arrangement32_rom(input wire clk,input wire [12:0] addr,output reg [15:0] data);',
       f'wire [31:0] q [0:{pages-1}]; reg [2:0] page;',
       'always @(posedge clk) page <= addr[12:10];', 'always @* begin case(page)']
    for p in range(pages): v.append(f"3'd{p}: data=q[{p}][15:0];")
    v+=['default: data=0; endcase end']
    padded=words+[0]*(pages*1024-len(words))
    for p in range(pages):
        v.append('pROM #(.READ_MODE(0),.BIT_WIDTH(16),.RESET_MODE("SYNC"),')
        for k in range(64):
            value=sum(padded[p*1024+k*16+i]<<(16*i) for i in range(16))
            v.append(f".INIT_RAM_{k:02X}(256'h{value:064x})"+(',' if k<63 else ''))
        v.append(f') bank{p}(.DO(q[{p}]),.AD({{addr[9:0],4\'b0}}),.CLK(clk),.CE(1\'b1),.OCE(1\'b1),.RESET(1\'b0));')
    v.append('endmodule')
    (ROOT/'rtl/audio/arrangement32_rom.v').write_text('\n'.join(v)+'\n')
    out.mkdir(parents=True,exist_ok=True)
    (out/'arrangement32.json').write_text(json.dumps(dict(rom_words=len(words),bsram_pages=pages,songs=[sa,sb]),indent=2))
    return [sa,sb]

def load_rtl_tables():
    # Decode the actual synthesis pROM initializers, including the existing
    # band limiting. No substitute piano/sine-harmonic synthesizer is used.
    source=(ROOT/'rtl/audio/gowin_prom_piano_bank.v').read_text()
    blocks=re.findall(r"\.INIT_RAM_[0-9A-F]{2}\(256'h([0-9a-fA-F]+)\)",source)
    values=[(int(block,16)>>(16*i))&65535 for block in blocks for i in range(16)]
    bank=np.array(values,dtype=np.int64).reshape(12,512)
    bank=np.where(bank>=32768,bank-65536,bank)
    sine=np.array([int(x,16) for x in (ROOT/'rtl/audio/wave_sine.hex').read_text().split()],dtype=np.int64)
    sine=np.where(sine>=32768,sine-65536,sine)
    return bank,sine

def render_voice(bank,sine,note,velocity,gate_samples):
    # RAM32 equations: F=8 interpolation, time-driven stage cross-fade,
    # 140/16/48 ADSR, envelope rounding before 7-bit velocity rounding.
    duration=gate_samples+1366
    age=np.arange(duration,dtype=np.int64)
    env=np.where(age<469,np.minimum((age+1)*140,65535),
                 np.maximum(45875,65535-(age-468)*16))
    at_release=int(env[max(0,gate_samples-1)])
    env[gate_samples:]=np.maximum(at_release-(np.arange(duration-gate_samples)+1)*48,0)
    base=(749115,793660,840854,890853,943826,999949,1059409,1122405,1189147,1259857,1334772,1414142)
    inc=base[note%12]<<(note//12)
    phase=(age*inc)&0xffffffff
    index=(phase>>23)&511;frac=(phase>>14)&511
    stage=np.minimum(age//8192,3)
    timer=np.where(stage==3,8191,age%8192)
    low=(6 if note>=78 else 0)+3-stage
    weight=(8191-timer)<<3
    def interp(table):
        a=table[index];b=table[(index+1)&511]
        return (a<<8)+(((b-a)*frac+1)>>1)
    sa=interp(sine)
    a=bank[low,index];b=bank[low,(index+1)&511]
    ba=(a<<8)+(((b-a)*frac+1)>>1)
    a=bank[low+1,index];b=bank[low+1,(index+1)&511]
    bb=(a<<8)+(((b-a)*frac+1)>>1)
    bright=ba+(((bb-ba)*weight+32768)>>16)
    sa=((((sa*env+32768)>>16)*velocity+64)>>7)
    bright=((((bright*env+32768)>>16)*velocity+64)>>7)
    return sa,bright

def preview(score,path):
    # Same score, actual table contents and DSP arithmetic; configuration
    # latency and the analog DAC are outside this offline listening model.
    fs=46875
    unit_samples=round(60/score['bpm']/4*fs)
    size=score['units']*unit_samples+round(.3*fs)
    sine_sum=np.zeros(size,dtype=np.int64);bright_sum=np.zeros(size,dtype=np.int64)
    opened={};segments=[]
    for unit,word in score['events']:
        note=(word>>8)&127
        if word&0x8000:
            assert note not in opened
            opened[note]=(unit,word&127)
        else:
            start,velocity=opened.pop(note)
            segments.append((start*unit_samples,(unit-start)*unit_samples,note,velocity))
    assert not opened
    bank,sine=load_rtl_tables()
    occupancy=[]
    for start,gate,note,velocity in segments:
        sa,ba=render_voice(bank,sine,note,velocity,gate)
        end=min(size,start+len(sa))
        sine_sum[start:end]+=sa[:end-start];bright_sum[start:end]+=ba[:end-start]
        occupancy.extend([(start,1),(min(size,start+gate+math.ceil(45875/48)),-1)])
    # Default board blend is 64/255. The 32-voice master headroom is /32.
    mix=(sine_sum*255+(bright_sum-sine_sum)*64+(1<<12))>>13
    y=mix.astype(np.float64)/8388608
    raw_peak=float(np.max(np.abs(y)))
    # Listening gain only, stated in the metrics; no limiter or added reverb.
    gain=.82/max(raw_peak,1e-9);y*=gain
    current=peak_voices=0
    for _,delta in sorted(occupancy): current+=delta;peak_voices=max(peak_voices,current)
    assert peak_voices<=32, peak_voices
    with wave.open(str(path),'wb') as w:
        w.setparams((1,2,fs,0,'NONE','not compressed')); w.writeframes((y*32767).astype('<i2').tobytes())
    return dict(file=path.name,seconds=len(y)/fs,peak_dbfs=20*math.log10(max(np.max(np.abs(y)),1e-9)),
                sample_rate=fs,preview_gain_db=20*math.log10(gain),peak_gated_notes=score['peak_gated_notes'],
                peak_voices_with_release=peak_voices,
                timbre='actual synthesis pROM tables, default blend64, RAM32 envelope/interpolation; no DAC/config-latency model')

if __name__=='__main__':
    import sys
    out=Path(sys.argv[1]) if len(sys.argv)>1 else ROOT/'../artifacts/arrangement32'
    scores=generate(out)
    results=[preview(s,out/('wanye32.wav' if s['song']==0 else 'kuanggu32.wav')) for s in scores]
    (out/'preview_metrics.json').write_text(json.dumps(results,indent=2))
    print(json.dumps(results)); print([(s['song'],s['peak_gated_notes']) for s in scores])
