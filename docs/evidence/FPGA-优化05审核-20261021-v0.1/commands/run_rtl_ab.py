"""One short old/new engine comparison, retaining pre-compaction ROM primitives."""
from pathlib import Path
import csv,hashlib,json,subprocess,shutil
ROOT=next(p for p in Path(__file__).resolve().parents if (p/'.git').exists())
OUT=Path(__file__).resolve().parents[1]
SRC=ROOT/'output/handoff_milestone2_20261008/source'
OLD=ROOT/'archive/FPGA-20261021-v0.6/source'
WORK=ROOT/'tmp/bank-review-20261021-v01';WORK.mkdir(parents=True,exist_ok=True)
(OUT/'source').mkdir(exist_ok=True);(OUT/'before').mkdir(exist_ok=True)
names=['shared_wavetable_engine','gowin_prom_piano_bank','gowin_prom_guitar_bank']
refs=[]
for name in names:
    data=(OLD/'rtl/audio'/f'{name}.v').read_text(encoding='utf-8-sig')
    (OUT/'before'/f'{name}.v').write_text(data,encoding='utf-8')
    for item in names:data=data.replace(item,'old_'+item)
    path=WORK/f'old_{name}.v';path.write_text(data,encoding='utf-8');refs.append(path)
connections=['.clk(clk)', '.rst(rst)', '.sample_tick(tick)']
for i in range(8):
    connections.extend([f'.inc{i}('+('inc' if i==0 else "32'd0")+')',
        f'.env{i}('+('env' if i==0 else "16'd0")+')',
        f'.vel{i}('+('velocity' if i==0 else "8'd0")+')',
        f'.note{i}('+('note' if i==0 else "7'd0")+')',
        f'.retrig{i}('+('retrigger' if i==0 else "1'b0")+')'])
connections.extend(['.piano_enable(kind==1)', '.guitar_enable(kind==2)', '.piano_tone(tone)',
    ".bend_ratio_q16(17'd65536)",'.mult_result(36\'sd0)', '.mult_request()', '.mult_operand_a()', '.mult_operand_b()'])
params=' #(.BEND_SHARED_ENABLE(1),.BANDLIMIT_ENABLE(1),.GENERIC_BRIGHT_ENABLE(1),.GUITAR_ENABLE(1),.KEY_GAIN_ENABLE(1),.ZONE_LATCH_ENABLE(1),.STAGE_TIME_ENABLE(1),.STAGE_STEP_SAMPLES(8),.VOICES8(1),.EXTRA_FRACTION_BITS(2)) '
instances=[]
for module,label in [('shared_wavetable_engine','new'),('old_shared_wavetable_engine','old')]:
    instances.append(module+params+label+'_dut('+','.join(connections+[f'.sine_sum({label}_s)',f'.bright_sum({label}_b)',f'.sums_valid({label}_v)'])+');')
bench='''`timescale 1ns/1ps
module tb_bank_audio_ab;
reg clk=0;always #5 clk=~clk;
reg rst=1,tick=0,retrigger=0;
reg [31:0] inc=0;reg [15:0] env=65535;reg [7:0] velocity=100;
reg [6:0] note=60;reg [2:0] tone=0;integer kind=1;
wire signed [20:0] old_s,old_b,new_s,new_b;wire old_v,new_v;
'''+ '\n'.join(instances)+'''
integer cfg,results,code,n,k,v,t,increment,c,frame,cycles,total=0,delta;
reg [2047:0] cases_path,results_path;
initial begin
 if(!$value$plusargs("cases=%s",cases_path) || !$value$plusargs("results=%s",results_path))$fatal(1,"missing paths");
 cfg=$fopen(cases_path,"r");results=$fopen(results_path,"w");
 if(!cfg || !results)$fatal(1,"file open failed");
 $fdisplay(results,"kind,note,velocity,tone,frame,env,old,new");
 while(!$feof(cfg))begin
  code=$fscanf(cfg,"%d %d %d %d %d\\n",k,n,v,t,increment);
  if(code==5)begin
   rst=1;repeat(3)@(negedge clk);kind=k;note=n;velocity=v;tone=t;inc=increment;rst=0;
   for(frame=0;frame<64;frame=frame+1)begin
    case(frame%6) 0:env=0;1:env=1;2:env=256;3:env=8192;4:env=32768;5:env=65535;endcase
    retrigger=(frame==0);tick=1;@(negedge clk);tick=0;
    cycles=0;
    while(!new_v || !old_v)begin
     @(negedge clk);cycles=cycles+1;
     if(new_v!==old_v || cycles>500)$fatal(1,"frame timing changed");
    end
    if((^old_b===1'bx)||(^new_b===1'bx)||old_s!==new_s)$fatal(1,"unknown result or sine changed");
    delta=$signed(new_b)-$signed(old_b);
    if(k!=1 && delta!=0)$fatal(1,"unchanged instrument differs");
    if(delta>324 || delta< -324)$fatal(1,"piano exceeds table-derived error bound: %0d",delta);
    $fdisplay(results,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",k,n,v,t,frame,env,$signed(old_b),$signed(new_b));
    total=total+1;@(negedge clk);
   end
  end
 end
 $fclose(cfg);$fclose(results);$display("PASS tb_bank_audio_ab: %0d paired frames, mapping/timing/sine unchanged, guitar exact, piano bounded",total);$finish;
end
initial begin #50000000;$fatal(1,"timeout");end
endmodule
'''
tb=OUT/'source/tb_bank_audio_ab.v';tb.write_text(bench,encoding='utf-8')
cases=[]
for note in [24,36,48,60,72,84,95]:
    for tone in [0,1,2,3,4]:cases.append((1,note,127,tone))
for note in [40,52,64,71,80,88]:
    for vel in [0,1,31,32,63,64,95,96,111,112,127]:cases.append((2,note,vel,0))
for note in [36,72,95]:cases.append((0,note,100,0))
casefile=OUT/'cases.txt';casefile.write_text(''.join(f'{k} {n} {v} {t} {round(440*2**((n-69)/12)/46875*2**32)}\n' for k,n,v,t in cases),encoding='ascii')
# Windows vvp cannot fopen Unicode paths; file IO uses the ASCII temp directory.
shutil.copy2(casefile,WORK/'cases.txt')
inputs=[*sorted((SRC/'rtl/audio').glob('*.v')),SRC/'sim/gowin_prom_model.v',*refs,tb]
binary=WORK/'tb_bank_audio_ab.vvp'
commands=[('compile',['C:/iverilog/bin/iverilog.exe','-g2012','-DSIMULATION','-I','.', '-s','tb_bank_audio_ab','-o',binary,*inputs]),
    ('run',['C:/iverilog/bin/vvp.exe',binary,'+cases='+(WORK/'cases.txt').as_posix(),'+results='+(WORK/'rtl_pairs.csv').as_posix()])]
checks=[]
for step,cmd in commands:
    try:
        p=subprocess.run([str(x) for x in cmd],cwd=SRC,capture_output=True,timeout=60)
        data=p.stdout+p.stderr;code=p.returncode
    except subprocess.TimeoutExpired as e:data=(e.stdout or b'')+(e.stderr or b'')+b'\nTIMEOUT';code=124
    (OUT/f'rtl_ab_{step}.log').write_bytes(data)
    ok=code==0 and (step=='compile' or b'PASS tb_bank_audio_ab' in data)
    checks.append(dict(step=step,exit=code,passed=ok));print(step,code,ok,flush=True)
    if not ok:break
result=dict(cases=len(cases),frames_per_case=64,checks=checks,passed=len(checks)==2 and all(x['passed'] for x in checks),
    stage_step_accelerated_from=5859,stage_step_used=8,full_gate=False,
    inputs_sha256={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs})
(OUT/'rtl_ab_results.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
if (WORK/'rtl_pairs.csv').exists():shutil.copy2(WORK/'rtl_pairs.csv',OUT/'rtl_pairs.csv')
raise SystemExit(0 if result['passed'] else 1)
