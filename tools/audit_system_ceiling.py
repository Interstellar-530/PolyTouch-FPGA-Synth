"""Measure current RTL and bound proposed architectures; never alter production RTL.

The alias metric is the power in source-table partials beyond Nyquist divided
by source-table AC power. It predicts folding; it is not DAC THD or SINAD.
"""
from pathlib import Path
import argparse,csv,json,math,subprocess,sys
import numpy as np

TB=r'''
`timescale 1ns/1ps
module tb_ceiling;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,tick=0;reg[6:0]note=60;reg[16:0]ratio=65536;
 wire[31:0]base_inc;wire signed[18:0]sine_sum,bright_sum;
 wire valid;wire signed[15:0]sample;
 note_phase_inc #(.FS_HZ(48000)) npi(note,base_inc);
 shared_wavetable_engine #(.BEND_SHARED_ENABLE(1)) core(
 .clk(clk),.rst(rst),.sample_tick(tick),
 .inc0(base_inc),.inc1(32'd0),.inc2(32'd0),.inc3(32'd0),
 .retrig0(1'b0),.retrig1(1'b0),.retrig2(1'b0),.retrig3(1'b0),
 .env0(16'd65535),.env1(16'd0),.env2(16'd0),.env3(16'd0),
 .vel0(8'd127),.vel1(8'd0),.vel2(8'd0),.vel3(8'd0),
 .bend_ratio_q16(ratio),.sine_sum(sine_sum),.bright_sum(bright_sum),.sums_valid(valid));
 global_crossfade #(.MASTER_VOLUME_SHIFT(2)) xf(.clk(clk),.rst(rst),.update(valid),
 .clear_clip(1'b0),.mix_weight(8'd255),.sine_sum(sine_sum),.bright_sum(bright_sum),.sample_out(sample));
 integer notes[0:6];integer fd,c,n;reg[2047:0]capture;
 initial begin
  if(!$value$plusargs("CAPTURE=%s",capture))$fatal(1,"capture missing");
  fd=$fopen(capture,"w");if(!fd)$fatal(1,"capture open");
  $fwrite(fd,"case_id,note,ratio_q16,base_inc,frame,phase,sine_sum,bright_sum,sample\n");
  notes[0]=60;notes[1]=71;notes[2]=89;notes[3]=91;notes[4]=96;notes[5]=108;notes[6]=127;
  for(c=0;c<7;c=c+1)begin
   rst=1;tick=0;note=notes[c];ratio=c==2?17'd73562:17'd65536;
   repeat(4)@(negedge clk);rst=0;
   for(n=0;n<8192;n=n+1)begin
    tick=1;@(negedge clk);tick=0;
    wait(valid);repeat(2)@(negedge clk);
    if(^sample===1'bx || ^sine_sum===1'bx || ^bright_sum===1'bx)$fatal(1,"unknown output");
    $fwrite(fd,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d\n",c,note,ratio,base_inc,n,core.phase0,sine_sum,bright_sum,sample);
    repeat(2)@(negedge clk);
   end
  end
  $fclose(fd);$display("PASS tb_ceiling: 7 pitches, 8192 actual RTL frames per case, no unknown output");$finish;
 end
 initial begin #100000000;$fatal(1,"ceiling capture timeout");end
endmodule
'''

def read_wave(path):
    raw=np.array([int(v,16) for v in path.read_text().split()],dtype=np.int64)
    return np.where(raw>=32768,raw-65536,raw)

def interpolate(wave,phase):
    index=(phase>>23)&511;frac=(phase>>14)&511
    return wave[index]+(((wave[(index+1)&511]-wave[index])*frac+256)>>9)

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--out',type=Path);parser.add_argument('--reuse-capture',action='store_true');parser.add_argument('--control-only',action='store_true');args=parser.parse_args()
    root=Path(__file__).resolve().parents[1]
    source=root/'output/handoff_milestone2_20261008/source'
    work=root/'tmp/system-ceiling-20261017';work.mkdir(parents=True,exist_ok=True)
    out=args.out or root/'docs/evidence/FPGA-整体潜力审查-20261017-v0.1';out.mkdir(parents=True,exist_ok=True)
    if args.control_only:
        probe=out/'control-probe';bench=probe/'tb_pressure_duplicate.v'
        local_bench=work/'tb_pressure_duplicate.v';local_bench.write_bytes(bench.read_bytes())
        exe=work/'control-probe.vvp'
        command=[r'C:\iverilog\bin\iverilog.exe','-g2012','-DSIMULATION','-I',str(source),'-s','tb_pressure_duplicate','-o',str(exe),str(local_bench),str(source/'rtl/top.v')]
        command+=list(map(str,sorted((source/'rtl/audio').glob('*.v'))))+[str(source/'sim/gowin_prom_model.v'),str(source/'sim/mcp3208_model.v')]
        for label,cmd in [('compile',command),('run',[r'C:\iverilog\bin\vvp.exe',str(exe)])]:
            cp=subprocess.run(cmd,cwd=source,capture_output=True,timeout=150)
            (probe/(label+'.log')).write_bytes(cp.stdout+cp.stderr)
            if cp.returncode:raise RuntimeError((cp.stdout+cp.stderr).decode('utf-8','replace'))
        print('PASS: current pressure duplication and raw bend-noise behavior reproduced (defect observation, not product acceptance).')
        return
    tb=work/'tb_ceiling.v';tb.write_text(TB,encoding='ascii')
    exe=work/'tb_ceiling.vvp';capture=work/'ceiling.csv'
    sources=list((source/'rtl/audio').glob('*.v'))+[source/'sim/gowin_prom_model.v']
    command=[r'C:\iverilog\bin\iverilog.exe','-g2012','-DSIMULATION','-I',str(source),'-s','tb_ceiling','-o',str(exe),str(tb)]+list(map(str,sources))
    if not args.reuse_capture:
        cp=subprocess.run(command,cwd=source,capture_output=True)
        (out/'compile.log').write_bytes(cp.stdout+cp.stderr)
        if cp.returncode:raise RuntimeError(cp.stderr.decode('utf-8','replace'))
        cp=subprocess.run([r'C:\iverilog\bin\vvp.exe',str(exe),'+CAPTURE='+str(capture)],cwd=source,capture_output=True,timeout=150)
        (out/'simulation.log').write_bytes(cp.stdout+cp.stderr)
        if cp.returncode:raise RuntimeError(cp.stdout.decode('utf-8','replace'))
    elif not capture.exists():
        capture=out/'ceiling.csv'
    rows=list(csv.DictReader(capture.open()))
    sine=read_wave(source/'rtl/audio/wave_sine.hex');bright=read_wave(source/'rtl/audio/wave_bright.hex')
    spectrum=np.abs(np.fft.rfft(bright))**2;spectrum[0]=0
    assert sum(spectrum[1:17])/sum(spectrum)>.999999
    reports=[]
    for case_id in range(7):
        group=[row for row in rows if int(row['case_id'])==case_id]
        phase=np.array([int(row['phase']) for row in group],dtype=np.int64)
        inc=int(group[0]['base_inc']);ratio=int(group[0]['ratio_q16']);step=(inc*ratio>>16)&0xffffffff
        assert np.all(phase==np.mod(np.arange(1,len(group)+1,dtype=np.int64)*step,2**32))
        for wave,key in [(sine,'sine_sum'),(bright,'bright_sum')]:
            reference=(((interpolate(wave,phase)*65535)>>16)*127)>>7
            actual=np.array([int(row[key]) for row in group])
            assert np.array_equal(reference,actual),(case_id,key,int(np.max(np.abs(reference-actual))))
        samples=np.array([int(row['sample']) for row in group])
        reference=((((interpolate(bright,phase)*65535)>>16)*127)>>7)
        reference=((reference*255+127)>>8)>>2
        assert np.array_equal(samples,reference),(case_id,'sample')
        frequency=step*48000/2**32
        unsafe=np.arange(len(spectrum))*frequency>=24000
        folded=float(spectrum[unsafe].sum()/spectrum.sum())
        reports.append(dict(note=int(group[0]['note']),bend_semitones=2 if case_id==2 else 0,
            frames=len(group),actual_fundamental_hz=frequency,peak_abs=int(max(abs(samples))),
            source_out_of_band_power_db=10*math.log10(max(folded,1e-30)),
            rtl_bit_exact=True))
    # Pure arithmetic lower bounds, excluding new state RAM and control overhead.
    budgets=[]
    for voices in [4,8,12,32,64,128]:
        cycles=19*voices+5
        budgets.append(dict(voices=voices,cycles_lower_bound=cycles,
            minimum_compute_clock_hz=cycles*48000,throughput_oscillator_samples_s=voices*48000,
            single_voice_loss_db_vs_current_four=20*math.log10(voices/4)))
    # Additional numerical model: fit a sine and DC term, then measure residual.
    # This is the steady-state fixed-point limit, not a physical noise reading.
    phase=np.mod(np.arange(1,48001,dtype=np.int64)*39370528,2**32)
    angle=phase*(2*math.pi/2**32)
    design=np.column_stack([np.sin(angle),np.cos(angle),np.ones(len(phase))])
    precision=[]
    for env in [65535,256]:
        for gain in [4096,1024]:
            value=(((interpolate(sine,phase)*env)>>16)*100)>>7
            value=(((value*255+127)>>8)>>2)*gain>>12
            fit=np.linalg.lstsq(design,value,rcond=None)[0]
            residual=value-design@fit
            snr=10*math.log10((fit[0]**2+fit[1]**2)/2/np.mean(residual**2))
            precision.append(dict(measurement='integer model',env=env,velocity=100,gain_q12=gain,
                                  sine_residual_snr_db=float(snr),dc_lsb=float(fit[2])))
    result=dict(measurement='actual RTL + independent integer model; spectral folding estimate from source table',
        captured_frames=len(rows),rtl_reference_mismatches=0,pitch_cases=reports,
        schedule_lower_bounds=budgets,precision_model=precision,notes='Captured frame cadence is accelerated; pitch increments model 48 kHz. Output clock timing remains covered by the prior top-level I2S tests. Source out-of-band power is not analog THD or folded-bin SINAD.')
    (out/'metrics.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    (out/'ceiling.csv').write_bytes(capture.read_bytes())
    (out/'tb_ceiling.v').write_text(TB,encoding='ascii')
    print(json.dumps(result,indent=2),flush=True)

if __name__=='__main__':main()
