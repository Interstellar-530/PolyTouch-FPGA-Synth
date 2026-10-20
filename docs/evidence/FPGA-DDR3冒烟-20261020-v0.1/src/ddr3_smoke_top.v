`timescale 1ps/1ps
// Minimal DDR3 calibration/read-write smoke test, based on Sipeed's
// LicheeTang20K_DDR_Test (BSD-3-Clause). The only functional fix is that
// the controller's chip-select output drives ddr_cs instead of a floating net.
module ddr3_smoke_top (
    input wire clk,
    output wire [13:0] ddr_addr,
    output wire [2:0] ddr_bank,
    output wire ddr_cs,
    output wire ddr_ras,
    output wire ddr_cas,
    output wire ddr_we,
    output wire ddr_ck,
    output wire ddr_ck_n,
    output wire ddr_cke,
    output wire ddr_odt,
    output wire ddr_reset_n,
    output wire [1:0] ddr_dm,
    inout wire [15:0] ddr_dq,
    inout wire [1:0] ddr_dqs,
    inout wire [1:0] ddr_dqs_n,
    output wire uart_txp,
    output wire led
);
    wire memory_clk;
    wire pll_lock;
    wire rst_n;
    wire clk_x1;
    wire [26:0] app_addr;
    wire app_cmd_en;
    wire [2:0] app_cmd;
    wire app_cmd_rdy;
    wire app_wren;
    wire app_data_end;
    wire [127:0] app_data;
    wire app_data_rdy;
    wire app_rdata_valid;
    wire app_rdata_end;
    wire [127:0] app_rdata;
    wire init_calib_complete;
    wire [5:0] app_burst_number;

    assign led = init_calib_complete;

    tester test (
        .clk(clk), .rst_n(rst_n), .clk_x1(clk_x1), .app_addr(app_addr),
        .app_cmd_en(app_cmd_en), .app_cmd(app_cmd), .app_cmd_rdy(app_cmd_rdy),
        .app_wren(app_wren), .app_data_end(app_data_end), .app_data(app_data),
        .app_data_rdy(app_data_rdy), .app_rdata_valid(app_rdata_valid),
        .app_rdata_end(app_rdata_end), .app_rdata(app_rdata),
        .init_calib_complete(init_calib_complete),
        .app_burst_number(app_burst_number), .txp(uart_txp)
    );

    Gowin_rPLL pll (
        .clkout(memory_clk), .lock(pll_lock), .reset(~rst_n), .clkin(clk)
    );

    DDR3_Memory_Interface_Top u_ddr3 (
        .clk(clk), .memory_clk(memory_clk), .pll_lock(pll_lock), .rst_n(rst_n),
        .app_burst_number(app_burst_number), .cmd_ready(app_cmd_rdy),
        .cmd(app_cmd), .cmd_en(app_cmd_en), .addr({1'b0, app_addr}),
        .wr_data_rdy(app_data_rdy), .wr_data(app_data), .wr_data_en(app_wren),
        .wr_data_end(app_data_end), .wr_data_mask(16'h0000),
        .rd_data(app_rdata), .rd_data_valid(app_rdata_valid),
        .rd_data_end(app_rdata_end), .sr_req(1'b0), .ref_req(1'b0),
        .sr_ack(), .ref_ack(), .init_calib_complete(init_calib_complete),
        .clk_out(clk_x1), .burst(1'b1), .ddr_rst(),
        .O_ddr_addr(ddr_addr), .O_ddr_ba(ddr_bank), .O_ddr_cs_n(ddr_cs),
        .O_ddr_ras_n(ddr_ras), .O_ddr_cas_n(ddr_cas), .O_ddr_we_n(ddr_we),
        .O_ddr_clk(ddr_ck), .O_ddr_clk_n(ddr_ck_n), .O_ddr_cke(ddr_cke),
        .O_ddr_odt(ddr_odt), .O_ddr_reset_n(ddr_reset_n), .O_ddr_dqm(ddr_dm),
        .IO_ddr_dq(ddr_dq), .IO_ddr_dqs(ddr_dqs), .IO_ddr_dqs_n(ddr_dqs_n)
    );
endmodule