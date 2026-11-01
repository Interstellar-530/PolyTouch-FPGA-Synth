"""Independent, bounded review of optimization 01. Does not edit product sources."""
from pathlib import Path
import hashlib
import json
import re
import subprocess

ROOT = next(p for p in Path(__file__).resolve().parents if (p / '.git').exists())
OUT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'output/handoff_milestone2_20261008/source'
WORK = ROOT / 'tmp/velocity-review-20261021-v01'
ENGINE = SOURCE / 'rtl/audio/shared_wavetable_engine.v'
PYTHON_TOOL = 'C:/iverilog/bin/iverilog.exe'
VVP = 'C:/iverilog/bin/vvp.exe'
ROWS = []


def command(name, args, expected=0, marker=None, timeout=60):
    try:
        result = subprocess.run([str(x) for x in args], cwd=SOURCE,
                                capture_output=True, timeout=timeout)
        code, data = result.returncode, result.stdout + result.stderr
    except subprocess.TimeoutExpired as error:
        code = 124
        data = (error.stdout or b'') + (error.stderr or b'') + b'\nTIMEOUT\n'
    (OUT / f'{name}.log').write_bytes(data)
    passed = code == expected and (marker is None or marker.encode() in data)
    ROWS.append(dict(check=name, exit=code, expected_exit=expected, passed=passed))
    print(f'{name}: exit={code} accepted={passed}', flush=True)
    return passed


def paired_bench():
    text = r'''`timescale 1ns/1ps
module tb_review_velocity_equivalence;
reg clk=0; always #5 clk=~clk;
reg rst=1,tick=0,piano=1,guitar=0;
reg [31:0] inc[0:7]; reg [15:0] env[0:7];
reg [7:0] raw_velocity[0:7],reference_velocity[0:7];
reg [6:0] note[0:7]; reg [7:0] retrig=0;
reg [16:0] ratio=17'd65536;
wire [2:0] nv,rv,nreq,rreq;
wire signed [20:0] ns[0:2],nb[0:2],rs[0:2],rb[0:2];
wire signed [17:0] na[0:2],nbop[0:2],ra[0:2],rbop[0:2];
'''
    configs = [dict(VOICES8=0, EXTRA_FRACTION_BITS=0, SHARED_MULT_ENABLE=0,
                    BEND_SHARED_ENABLE=0, BANDLIMIT_ENABLE=0, KEY_GAIN_ENABLE=1),
               dict(VOICES8=1, EXTRA_FRACTION_BITS=2, SHARED_MULT_ENABLE=1,
                    BEND_SHARED_ENABLE=1, BANDLIMIT_ENABLE=1, KEY_GAIN_ENABLE=1,
                    GENERIC_BRIGHT_ENABLE=1, GUITAR_ENABLE=1, ZONE_LATCH_ENABLE=1,
                    STAGE_TIME_ENABLE=1),
               dict(VOICES8=1, EXTRA_FRACTION_BITS=2, SHARED_MULT_ENABLE=0,
                    BEND_SHARED_ENABLE=0, BANDLIMIT_ENABLE=0, KEY_GAIN_ENABLE=0)]
    for lane, config in enumerate(configs):
        width = 19 + config['EXTRA_FRACTION_BITS']
        params = ','.join(f'.{k}({v})' for k, v in config.items())
        for tag, module, velocity in [('n','shared_wavetable_engine','raw_velocity'),
                                      ('r','review_baseline_engine','reference_velocity')]:
            text += f'wire signed [{width-1}:0] {tag}s{lane},{tag}b{lane};\n'
            text += f'reg signed [35:0] {tag}prod{lane}=0;\n'
            text += f'always @(posedge clk) if({tag}req[{lane}]) {tag}prod{lane}<={tag}a[{lane}]*{tag}bop[{lane}];\n'
            ports = ['.clk(clk)', '.rst(rst)', '.sample_tick(tick)']
            for i in range(8):
                ports += [f'.inc{i}(inc[{i}])', f'.env{i}(env[{i}])',
                          f'.vel{i}({velocity}[{i}])', f'.note{i}(note[{i}])',
                          f'.retrig{i}(retrig[{i}])']
            ports += ['.piano_enable(piano)', '.guitar_enable(guitar)', '.piano_tone(3\'d4)',
                      '.bend_ratio_q16(ratio)', f'.sine_sum({tag}s{lane})',
                      f'.bright_sum({tag}b{lane})', f'.sums_valid({tag}v[{lane}])',
                      f'.mult_request({tag}req[{lane}])', f'.mult_operand_a({tag}a[{lane}])',
                      f'.mult_operand_b({tag}bop[{lane}])', f'.mult_result({tag}prod{lane})']
            text += f'{module} #({params}) {tag}dut{lane}('+','.join(ports)+');\n'
            text += f'assign {tag}s[{lane}]=$signed({tag}s{lane}); assign {tag}b[{lane}]=$signed({tag}b{lane});\n'
    text += r'''
integer mode,v,i,j,cycle,frames=0,comparisons=0,negative_values=0,positive_values=0;
integer midframe_changes=0; reg [2:0] seen;
reg [31:0] seed=32'h613f2a09;
task set_reference;
 begin
  for(i=0;i<8;i=i+1)
   if(raw_velocity[i]>127) reference_velocity[i]=127;
   else reference_velocity[i]=raw_velocity[i];
 end
endtask
initial begin
 for(i=0;i<8;i=i+1)begin inc[i]=0;env[i]=0;raw_velocity[i]=0;reference_velocity[i]=0;note[i]=60;end
 repeat(4)@(negedge clk);rst=0;
 for(mode=0;mode<3;mode=mode+1)begin
  piano=(mode==0);guitar=(mode==1);
  for(v=0;v<256;v=v+1)begin
   for(i=0;i<8;i=i+1)begin
    seed={seed[30:0],seed[31]^seed[21]^seed[1]^seed[0]};
    raw_velocity[i]=(v+i*37)&255;
    env[i]=(v%19==0)?16'hffff:seed[15:0];
    if(v%23==0 && i==3)env[i]=0;
    note[i]=(v*7+i*19+mode*11)&127;
    inc[i]=32'd10000000+((v*83123+i*1122337)&32'h03ffffff);
    retrig[i]=(v%17==0);
   end
   ratio=17'd64000+(v*17);
   set_reference();tick=1;@(negedge clk);tick=0;
   cycle=0;seen=0;
   while(seen!=3'b111 && cycle<576)begin
    @(negedge clk);cycle=cycle+1;
    for(j=0;j<3;j=j+1)begin
     if(nv[j]!==rv[j] || nreq[j]!==rreq[j])
      $fatal(1,"schedule changed mode=%0d velocity=%0d lane=%0d cycle=%0d",mode,v,j,cycle);
     if(nreq[j] && (na[j]!==ra[j] || nbop[j]!==rbop[j]))
      $fatal(1,"multiplier operands differ mode=%0d velocity=%0d lane=%0d",mode,v,j);
     if(nv[j])begin
      if(seen[j])$fatal(1,"duplicate frame completion lane=%0d",j);
      if((^ns[j])===1'bx || (^nb[j])===1'bx || ns[j]!==rs[j] || nb[j]!==rb[j])
       $fatal(1,"signed result mismatch mode=%0d velocity=%0d lane=%0d got=%0d/%0d expected=%0d/%0d",mode,v,j,ns[j],nb[j],rs[j],rb[j]);
      seen[j]=1;comparisons=comparisons+1;
      if(ns[j]<0 || nb[j]<0)negative_values=negative_values+1;
      if(ns[j]>0 || nb[j]>0)positive_values=positive_values+1;
     end
    end
    if(cycle==(v%40)+1)begin
     for(i=0;i<8;i=i+1)raw_velocity[i]=255-raw_velocity[i];
     set_reference();midframe_changes=midframe_changes+1;
    end
   end
   if(seen!=3'b111)$fatal(1,"deadline mode=%0d velocity=%0d seen=%b",mode,v,seen);
   frames=frames+1;@(negedge clk);
  end
 end
 if(negative_values==0 || positive_values==0 || frames!=768 || comparisons!=2304)
  $fatal(1,"coverage missing frames=%0d comparisons=%0d positive=%0d negative=%0d",frames,comparisons,positive_values,negative_values);
 $display("PASS tb_review_velocity_equivalence: frames=%0d paired_results=%0d positive=%0d negative=%0d midframe_changes=%0d; 4/8 voices, local/shared, extra 0/2, piano/guitar/generic/bypass",frames,comparisons,positive_values,negative_values,midframe_changes);
 $finish;
end
initial begin #20000000;$fatal(1,"review timeout");end
endmodule
'''
    return text


def main():
    WORK.mkdir(parents=True, exist_ok=True)
    (OUT / 'source').mkdir(exist_ok=True)
    original = subprocess.check_output(['git','show','2d3db6c:output/handoff_milestone2_20261008/source/rtl/audio/shared_wavetable_engine.v'], cwd=ROOT)
    (WORK / 'original_engine.v').write_bytes(original)
    baseline = original.replace(b'module shared_wavetable_engine #(', b'module review_baseline_engine #(', 1)
    (WORK / 'review_baseline_engine.v').write_bytes(baseline)
    (OUT / 'source/review_baseline_engine.v').write_bytes(baseline)
    bench = OUT / 'source/tb_review_velocity_equivalence.v'
    bench.write_text(paired_bench(), encoding='utf-8')
    sources = sorted((SOURCE / 'rtl/audio').glob('*.v')) + [SOURCE / 'sim/gowin_prom_model.v']
    engine_hash = hashlib.sha256(ENGINE.read_bytes()).hexdigest()
    for name in ['tb_velocity_bounds', 'tb_key_gain', 'tb_frame_velocity']:
        binary = WORK / f'{name}.vvp'
        if command(name+'-compile', [PYTHON_TOOL,'-g2012','-DSIMULATION','-I','.', '-s',name,'-o',binary,SOURCE/f'sim/{name}.v',*sources]):
            command(name, [VVP,binary], marker='PASS')
    binary = WORK / 'before_bounds.vvp'
    old_sources = [p for p in sources if p != ENGINE] + [WORK / 'original_engine.v']
    if command('before_bounds-compile', [PYTHON_TOOL,'-g2012','-DSIMULATION','-I','.', '-s','tb_velocity_bounds','-o',binary,SOURCE/'sim/tb_velocity_bounds.v',*old_sources]):
        command('before_bounds', [VVP,binary], expected=1, marker='vel 128')
    binary = WORK / 'independent_equivalence.vvp'
    if command('independent_equivalence-compile', [PYTHON_TOOL,'-g2012','-DSIMULATION','-I','.', '-s','tb_review_velocity_equivalence','-o',binary,bench,WORK/'review_baseline_engine.v',*sources]):
        command('independent_equivalence', [VVP,binary], marker='PASS')
    for name in ['tb_generic_bright','tb_piano_engine','tb_piano_morph']:
        for label, inputs in [('before',old_sources),('after',sources)]:
            binary=WORK/f'{name}_{label}.vvp'
            if command(f'{name}_{label}-compile', [PYTHON_TOOL,'-g2012','-DSIMULATION','-I','.', '-s',name,'-o',binary,SOURCE/f'sim/{name}.v',*inputs]):
                command(f'{name}_{label}',[VVP,binary],expected=1,marker='FATAL:')
    evidence = ROOT/'docs/evidence/FPGA-优化01-力度边界-20261021'
    metrics = json.loads((evidence/'metrics_after.json').read_text(encoding='utf-8-sig'))
    mismatched = [name for name,sha in metrics['inputs_sha256'].items()
                  if not Path(name).is_file() or hashlib.sha256(Path(name).read_bytes()).hexdigest()!=sha]
    fs = Path(metrics['bitstream'])
    result = dict(reviewed_engine_sha256=engine_hash, engine_unchanged_during_review=(engine_hash==hashlib.sha256(ENGINE.read_bytes()).hexdigest()),
                  baseline='2d3db6c', checks=ROWS, checks_passed=all(row['passed'] for row in ROWS),
                  build_inputs_checked=len(metrics['inputs_sha256']), mismatched_build_inputs=mismatched,
                  bitstream_sha_matches=(hashlib.sha256(fs.read_bytes()).hexdigest()==metrics['bitstream_sha256']),
                  full_gate_run=False, hardware_programmed=False, product_sources_modified=False)
    (OUT/'review_results.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    assert result['checks_passed'] and not mismatched and result['bitstream_sha_matches'] and result['engine_unchanged_during_review']


if __name__ == '__main__':
    main()
