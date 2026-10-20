"""Build an isolated, USB/headphones-only bench image using unchanged production RTL.

The existing pressure_bend ADC_CENTER parameter is set to 0 while MISO is tied
low. After the first sample this is neutral bend. GPIO keys are tied released.
No test claim is made about the disconnected ADC, keyboard or pressure sensor.
"""
from pathlib import Path
import argparse,hashlib,json,re,subprocess,sys,time

ROOT=Path(__file__).resolve().parents[1]
SRC=ROOT/'output/handoff_milestone2_20261008/source'
EV=ROOT/'docs/evidence/FPGA-板载联调-20261018-v0.1'
WORK=ROOT/'tmp/board-only-20261018'
GW=Path('E:/Gowin/Gowin_V1.9.11.03_Education_x64/IDE/bin/gw_sh.exe')

TOP=r'''// Bench only: no external keys/ADC/oscillator/DAC connected.
module board_only_top(
    input wire clk_27m,key_rst,key_s1,key_s2,uart_rx,
    output wire hp_bck,hp_ws,hp_din,pa_en,
    output wire led,led_chord,led_t0,led_t1,uart_tx
);
    wire adc_cs_unused,adc_sck_unused,adc_mosi_unused;
    wire [3:0] fold_unused;
    wire i2s_bck_unused,i2s_lrck_unused,i2s_din_unused,xsmt_unused;
    top #(.AUDIO_IF(0)) u_top(
        .clk_27m(clk_27m),.clk_12m288(1'b0),
        .key_rst(key_rst),.key_s1(key_s1),.key_s2(key_s2),.uart_rx(uart_rx),
        .gpio_key_n(12'hfff),.adc_miso(1'b0),
        .adc_cs_n(adc_cs_unused),.adc_sck(adc_sck_unused),.adc_mosi(adc_mosi_unused),
        .hp_bck(hp_bck),.hp_ws(hp_ws),.hp_din(hp_din),.pa_en(pa_en),
        .led(led),.led_chord(led_chord),.led_t0(led_t0),.led_t1(led_t1),.uart_tx(uart_tx),
        .clip_fold(fold_unused),.i2s_bck(i2s_bck_unused),.i2s_lrck(i2s_lrck_unused),
        .i2s_din(i2s_din_unused),.dac_xsmt(xsmt_unused)
    );
    // Existing parameter, isolated bench calibration: constant zero => no bend.
    defparam u_top.u_bend.ADC_CENTER=12'd0;
endmodule
'''

TB=r'''`timescale 1ns/1ps
module tb_board_only;
    reg clk=0,rst=0,rx=1;
    always #18.5185 clk=~clk;
    wire bck,ws,din,pa,tx;
    board_only_top dut(.clk_27m(clk),.key_rst(rst),.key_s1(1'b1),.key_s2(1'b1),
        .uart_rx(rx),.hp_bck(bck),.hp_ws(ws),.hp_din(din),.pa_en(pa),.uart_tx(tx));
    integer cycles=0,last_tick=-1,ticks=0,accepted=0,frames=0;
    reg monitor=0,prev_tick=0,prev_ws=0,synced=0;
    reg [15:0] shift=0,left=0,reference=0;
    integer bits=0;
    always @(posedge clk) begin
        cycles=cycles+1;
        if(dut.u_top.u_uart.reply_ok)accepted=accepted+1;
        if(dut.u_top.u_uart.reply_err)$fatal(1,"valid UART command rejected");
        if(monitor)begin
            if(dut.u_top.gpio_key_n!==12'hfff)$fatal(1,"external key input not isolated");
            if(dut.u_top.bend_ratio_q16!==17'd65536)$fatal(1,"bend is not unity");
            if(dut.u_top.sample_tick)begin
                if(prev_tick || (last_tick>=0 && cycles-last_tick!=576))$fatal(1,"tick width/period");
                last_tick=cycles;ticks=ticks+1;
            end
            prev_tick=dut.u_top.sample_tick;
        end
    end
    always @(posedge bck)begin
        #1;
        if(!dut.u_top.por)begin
            if(!synced)begin
                if(prev_ws && !ws)begin synced=1;bits=1;shift={15'd0,din};reference=dut.u_top.g_pt8211.u_pt8211.frame_data;end
            end else if(ws==prev_ws)begin shift={shift[14:0],din};bits=bits+1;end
            else begin
                if(bits!=16)$fatal(1,"PT8211 word width");
                if(!prev_ws)begin left=shift;if(left!==reference)$fatal(1,"left serial decode mismatch");end
                else begin
                    if(shift!==left || shift!==reference)$fatal(1,"right serial decode mismatch");
                    frames=frames+1;reference=dut.u_top.g_pt8211.u_pt8211.frame_data;
                end
                shift={15'd0,din};bits=1;
            end
            prev_ws=ws;
        end
    end
    task byte_tx;input [7:0] value;integer k;
      begin @(negedge clk);rx=0;#8680;
        for(k=0;k<8;k=k+1)begin rx=value[k];#8680;end rx=1;#8680;end
    endtask
    task cmd;input string value;integer k,before_count;
      begin before_count=accepted;for(k=0;k<value.len();k=k+1)byte_tx(value[k]);byte_tx(13);
        #1000000;if(accepted!=before_count+1)$fatal(1,"UART command count %s",value);end
    endtask
    task wait_ticks;input integer count;
      begin repeat(count)begin @(posedge dut.u_top.sample_tick);@(negedge dut.u_top.sample_tick);end end
    endtask
    initial begin
        #100000;rst=1;wait(!dut.u_top.rst);#3000000;monitor=1;
        cmd("D0");wait_ticks(1600);
        cmd("M1");cmd("T0");cmd("N69");wait_ticks(600);
        if(dut.u_top.v_gate==0 || dut.u_top.final_sample===16'd0)$fatal(1,"A4 missing");
        if(dut.u_top.timbre_target!=0)$fatal(1,"T0 not applied");
        cmd("T255");wait_ticks(300);
        if(dut.u_top.timbre_target!=255 || dut.u_top.u_xf.weight_state!=255)$fatal(1,"T255 not applied");
        cmd("X");wait_ticks(1600);
        cmd("N60");cmd("N64");cmd("N67");cmd("N71");wait_ticks(600);
        if(dut.u_top.v_gate!==4'b1111)$fatal(1,"four voice chord missing");
        cmd("M0");wait_ticks(300);if(dut.u_top.final_sample!==16'd0)$fatal(1,"mute failed");
        cmd("M1");wait_ticks(300);if(dut.u_top.v_gate!==15)$fatal(1,"mute released chord");
        cmd("X");wait_ticks(2000);if(dut.u_top.v_gate!==0 || dut.u_top.final_sample!==16'd0)$fatal(1,"panic release failed");
        if(frames<6000 || ticks<6000 || !pa)$fatal(1,"insufficient decoded frames or PA disabled");
        $display("PASS tb_board_only: commands=%0d decoded_frames=%0d neutral_bend_ticks=%0d; UART, 4 voices, timbre, mute, release",accepted,frames,ticks);
        $finish;
    end
    initial begin #500000000;$fatal(1,"timeout");end
endmodule
'''


def prepare():
    (EV/'source').mkdir(parents=True,exist_ok=True);WORK.mkdir(parents=True,exist_ok=True)
    (EV/'source/board_only_top.v').write_text(TOP,encoding='utf-8')
    (EV/'source/tb_board_only.v').write_text(TB,encoding='utf-8')
    ports=set(re.findall(r'\b(?:input|output) wire ([^;]+?)[\n;)]',TOP))
    names={'clk_27m','key_rst','key_s1','key_s2','uart_rx','hp_bck','hp_ws','hp_din','pa_en','led','led_chord','led_t0','led_t1','uart_tx'}
    cst=[]
    for line in (SRC/'constraints/primer20k_dock3714.cst').read_text(encoding='utf-8-sig').splitlines():
        match=re.match(r'IO_(?:LOC|PORT)\s+"([^"]+)"',line)
        if match and match[1] in names:cst.append(line)
    assert len(cst)==28
    (EV/'source/board_only.cst').write_text('\n'.join(cst)+'\n',encoding='utf-8')
    sources=[SRC/x.strip() for x in (SRC/'build/sources.list').read_text().splitlines() if x.strip()]
    binding={str(x.relative_to(ROOT)):hashlib.sha256(x.read_bytes()).hexdigest() for x in sources}
    binding.update({str(x.relative_to(ROOT)):hashlib.sha256(x.read_bytes()).hexdigest() for x in (SRC/'rtl/audio').glob('*.hex')})
    (EV/'source_binding.json').write_text(json.dumps(binding,indent=2),encoding='utf-8')
    return sources


def main():
    global EV, WORK
    sys.stdout.reconfigure(encoding='utf-8',errors='replace')
    parser=argparse.ArgumentParser()
    parser.add_argument('stage',choices=['prepare','sim','build'])
    parser.add_argument('--evidence',type=Path,default=EV)
    parser.add_argument('--work',type=Path,default=WORK)
    a=parser.parse_args()
    EV=a.evidence.resolve();WORK=a.work.resolve()
    sources=prepare()
    if a.stage=='sim':
        exe=WORK/'tb_board_only.vvp'
        command=[r'C:\iverilog\bin\iverilog.exe','-g2012','-DSIMULATION','-I',str(SRC),'-s','tb_board_only','-o',str(exe),str(EV/'source/tb_board_only.v'),str(EV/'source/board_only_top.v')]+list(map(str,sources))+[str(SRC/'sim/gowin_prom_model.v')]
        for label,cmd in [('compile',command),('simulation',[r'C:\iverilog\bin\vvp.exe',str(exe)])]:
            result=subprocess.run(cmd,cwd=SRC,capture_output=True,timeout=300)
            (EV/f'board-only-{label}.log').write_bytes(result.stdout+result.stderr)
            (EV/f'board-only-{label}-result.json').write_text(json.dumps({'exit_code':result.returncode}),encoding='ascii')
            print(result.stdout.decode('utf-8','replace')[-1600:],flush=True)
            if result.returncode:print(result.stderr.decode('utf-8','replace'));raise SystemExit(result.returncode)
        (EV/'board-only-sim-passed.txt').write_text('PASS\n',encoding='ascii')
    if a.stage=='build':
        # Gowin's native reader cannot open non-ASCII source paths. Keep an
        # identical working copy in the task's ASCII temporary directory.
        for name in ['board_only_top.v','board_only.cst']:
            (WORK/name).write_bytes((EV/'source'/name).read_bytes())
        run=WORK/('gowin-'+str(time.time_ns()));project=run/'board_only';project.mkdir(parents=True,exist_ok=True)
        for header in (SRC/'rtl/audio').glob('*.vh'):
            dest=project/'rtl/audio'/header.name;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(header.read_bytes())
        tcl=[f'create_project -name board_only -dir {{{run.as_posix()}}} -pn GW2A-LV18PG256C8/I7 -device_version C',f'add_file {{{(WORK/"board_only_top.v").as_posix()}}}']
        tcl += [f'add_file {{{p.as_posix()}}}' for p in sources]
        tcl += [f'add_file {{{(WORK/"board_only.cst").as_posix()}}}',f'add_file {{{(SRC/"constraints/primer20k.sdc").as_posix()}}}',
                'set_option -top_module board_only_top','set_option -output_base_name board_only',f'cd {{{project.as_posix()}}}','run all']
        entry=WORK/'build_board_only.tcl';entry.write_text('\n'.join(tcl)+'\n',encoding='utf-8')
        (EV/'source/build_board_only.tcl').write_bytes(entry.read_bytes())
        with (EV/'gowin-build.log').open('wb') as log:
            result=subprocess.run([str(GW),str(entry)],cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,timeout=600)
        if result.returncode:raise SystemExit(result.returncode)
        fs=project/'impl/pnr/board_only.fs';assert fs.is_file() and fs.stat().st_size>0
        dest=EV/'board_only.fs';dest.write_bytes(fs.read_bytes())
        (EV/'bitstream-sha256.txt').write_text(hashlib.sha256(dest.read_bytes()).hexdigest()+'  board_only.fs\n',encoding='ascii')
        print('Built isolated board-only image; no programming performed.',flush=True)


if __name__=='__main__':main()
