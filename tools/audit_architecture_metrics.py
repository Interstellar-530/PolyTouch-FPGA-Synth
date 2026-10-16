"""Numerical headroom and timing bounds; no new audio behavior."""
from pathlib import Path
import json,math
import numpy as np

def main():
    root=Path(__file__).resolve().parents[1];source=root/'output/handoff_milestone2_20261008/source'
    out=root/'docs/evidence/FPGA-架构优化-20261016-v0.1';out.mkdir(parents=True,exist_ok=True)
    waves=[]
    for name in ['wave_sine.hex','wave_bright.hex']:
        values=np.array([int(x,16) for x in (source/'rtl/audio'/name).read_text().split()],dtype=np.int64)
        values=np.where(values>=32768,values-65536,values)
        waves.append((((values*65535)>>16)*100)>>7)
    headroom=[]
    for weight in [0,64,160,255]:
        samples=(((waves[0]*4*(255-weight)+waves[1]*4*weight+127)>>8)>>1)
        headroom.append(dict(weight=weight,peak=int(np.max(np.abs(samples))),
            clipped_points=int(np.sum((samples>32767)|(samples< -32768))),samples=512,
            attenuation_needed_db=float(20*np.log10(np.max(np.abs(samples))/32767))))
    anchors=[58400,61858,65536,69402,73530]
    errors=[]
    for adc in range(4096):
        semitone=2*(adc-2048)/(2047 if adc>=2048 else 2048)
        q=int(semitone*256);u=q+512;segment=min(u>>8,4);fraction=u&255
        ratio=anchors[segment] if segment==4 else anchors[segment]+((anchors[segment+1]-anchors[segment])*fraction>>8)
        errors.append(1200*math.log2(ratio/65536)-100*semitone)
    result=dict(
        standard=dict(clock_hz=12288000,fs_hz=48000,frame_cycles=256,voices=4,
            old_compute_cycles=84,new_core_cycles=76,new_complete_cycles=81,compute_us=81/12.288,
            remaining_cycles=175,bsram_blocks=2,products_per_frame=34,
            multiplier_register_enable_fraction=34/256,
            same_serial_lane_32_voice_cycles=32*19),
        worst_aligned_four_voice_headroom_velocity100=headroom,
        bend_continuous_adc_error=dict(max_abs_cents=max(map(abs,errors)),
            adc_at_max=max(range(4096),key=lambda k:abs(errors[k]))),
        control=dict(adc_start_rate_hz=2000,fresh_hz_per_channel=1000,
            standard_spi_hz=12288000/50,spi_transaction_us=19/(12288000/50)*1e6))
    (out/'architecture-metrics.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    print(json.dumps(result))

if __name__=='__main__':main()
