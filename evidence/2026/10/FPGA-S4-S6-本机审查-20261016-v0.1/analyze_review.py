"""Independent numerical checks; no production RTL is changed."""
from pathlib import Path
import argparse
import importlib.util
import json
import math


def main():
    p=argparse.ArgumentParser()
    p.add_argument('--snapshot', type=Path, required=True)
    a=p.parse_args()
    repo=a.snapshot.resolve()
    src=repo/'output/handoff_milestone2_20261008/source'
    spec=importlib.util.spec_from_file_location('bendref',src/'tools/pressure_bend_ref.py')
    ref=importlib.util.module_from_spec(spec);spec.loader.exec_module(ref)
    rows=[]
    for adc in range(4096):
        q=ref.bend_q8(adc);r=ref.bend_ratio_q16(q)
        exact_adc=(adc-2048)*2/(2047 if adc>=2048 else 2048)
        rows.append(dict(adc=adc,q8=q,ratio=r,
           interpolation_error_cent=1200*math.log2(r/65536)-100*q/256,
           full_mapping_error_cent=1200*math.log2(r/65536)-100*exact_adc))
    # Exact algebraic replacement for the default positive-half constant divider.
    for d in range(2048):
        assert d*512//2047 == (512 if d==2047 else d>>2)
    for adc in range(4096):
        d=abs(adc-2048)
        fast=(512 if d==2047 else d>>2) if adc>=2048 else -(d>>2)
        assert fast==ref.bend_q8(adc)
    sine=[int(x,16) for x in (src/'rtl/audio/wave_sine.hex').read_text().split()]
    bright=[int(x,16) for x in (src/'rtl/audio/wave_bright.hex').read_text().split()]
    sine=[x-65536 if x>=32768 else x for x in sine]
    bright=[x-65536 if x>=32768 else x for x in bright]
    maxerr=max(rows,key=lambda r:abs(r['full_mapping_error_cent']))
    clip=[]
    for env in (45875,65535):
        samples=[]
        for s,b in zip(sine,bright):
            ss=4*((s*env//65536)*100//128)
            bs=4*((b*env//65536)*100//128)
            val=((ss*191+bs*64+127)//256)//2
            samples.append(val)
        clip.append(dict(envelope=env,velocity=100,voices=4,weight=64,
          peak=max(abs(x) for x in samples),
          clipped_table_points=sum(x>32767 or x< -32768 for x in samples),points=512))
    result=dict(default_divider_replacement_exact_codes=4096,
      bend_worst_full_mapping=maxerr,
      bend_max_interpolation_error_cent=max(abs(r['interpolation_error_cent']) for r in rows),
      four_same_phase_mix=clip,
      engine=dict(voices=4,clocks=84,standard_budget=256,
        estimated_serial_32_clocks=32*21,parallel_4_engines_8_voices_clocks=8*21),
      conversion=dict(debug_sck_hz=27000000/(54*2),std_sck_hz=12288000/(25*2),
        debug_frame_us=19*54*2/27,std_frame_us=19*25*2/12.288,
        control_hz=2000,per_channel_fresh_sample_hz=1000),
      adc_unfiltered_bend_step_cent=100/256,
      mode_button_debounce_ms=dict(debug=1048576/27000,standard=1048576/12288),
      adsr_48k=dict(attack_full_ms=math.ceil(65535/140)/48,
        decay_to_sustain_ms=math.ceil((65535-45875)/16)/48,
        release_from_sustain_ms=math.ceil(45875/48)/48))
    dest=Path(__file__).with_name('numerical_metrics.json')
    dest.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(result,ensure_ascii=False,indent=2))


if __name__=='__main__':main()
