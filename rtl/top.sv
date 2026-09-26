`timescale 1ns / 1ps

module top #
(
    parameter integer C_S00_AXI_DATA_WIDTH = 32,
    parameter integer C_S00_AXI_ADDR_WIDTH = 17
)
(
    // 외부 AXI4-Lite Interface (32비트 표준)
    input wire  s_axi_aclk,
    input wire  s_axi_aresetn,
    input wire [C_S00_AXI_ADDR_WIDTH-1 : 0] s_axi_awaddr,
    input wire [2 : 0] s_axi_awprot,
    input wire  s_axi_awvalid,
    output wire  s_axi_awready,
    input wire [C_S00_AXI_DATA_WIDTH-1 : 0] s_axi_wdata,
    input wire [(C_S00_AXI_DATA_WIDTH/8)-1 : 0] s_axi_wstrb,
    input wire  s_axi_wvalid,
    output wire  s_axi_wready,
    output wire [1 : 0] s_axi_bresp,
    output wire  s_axi_bvalid,
    input wire  s_axi_bready,
    input wire [C_S00_AXI_ADDR_WIDTH-1 : 0] s_axi_araddr,
    input wire [2 : 0] s_axi_arprot,
    input wire  s_axi_arvalid,
    output wire  s_axi_arready,
    output wire [C_S00_AXI_DATA_WIDTH-1 : 0] s_axi_rdata,
    output wire [1 : 0] s_axi_rresp,
    output wire  s_axi_rvalid,
    input wire  s_axi_rready
);

    // 내부 연결 와이어
    wire        w_user_start;
    wire        w_user_done;
    
    // AXI 변환기 <-> BRAM Port A 연결 (8비트!)
    wire [16:0] w_axi_bram_addr;
    wire [7:0]  w_axi_bram_wdata; // 8bit
    wire        w_axi_bram_we;
    wire [7:0]  w_axi_bram_rdata; // 8bit

    // Controller <-> BRAM Port B 연결 (8비트)
    wire [16:0] w_ctrl_bram_addr_full;
    wire [7:0]  w_ctrl_bram_wdata;
    wire        w_ctrl_bram_we;
    wire        w_ctrl_bram_en;
    wire [7:0]  w_ctrl_bram_rdata;


    // [1] AXI Interface Wrapper (통역사)
    myip_v1_0 # ( 
        .C_S00_AXI_DATA_WIDTH(C_S00_AXI_DATA_WIDTH),
        .C_S00_AXI_ADDR_WIDTH(C_S00_AXI_ADDR_WIDTH)
    ) u_axi_interface (
        // AXI External Ports
        .s00_axi_aclk(s_axi_aclk),
        .s00_axi_aresetn(s_axi_aresetn),
        .s00_axi_awaddr(s_axi_awaddr),
        .s00_axi_awprot(s_axi_awprot),
        .s00_axi_awvalid(s_axi_awvalid),
        .s00_axi_awready(s_axi_awready),
        .s00_axi_wdata(s_axi_wdata),
        .s00_axi_wstrb(s_axi_wstrb),
        .s00_axi_wvalid(s_axi_wvalid),
        .s00_axi_wready(s_axi_wready),
        .s00_axi_bresp(s_axi_bresp),
        .s00_axi_bvalid(s_axi_bvalid),
        .s00_axi_bready(s_axi_bready),
        .s00_axi_araddr(s_axi_araddr),
        .s00_axi_arprot(s_axi_arprot),
        .s00_axi_arvalid(s_axi_arvalid),
        .s00_axi_arready(s_axi_arready),
        .s00_axi_rdata(s_axi_rdata),
        .s00_axi_rresp(s_axi_rresp),
        .s00_axi_rvalid(s_axi_rvalid),
        .s00_axi_rready(s_axi_rready),
        
        // Internal Connections (8-bit)
        .user_start(w_user_start),
        .user_done(w_user_done),
        .user_bram_addr(w_axi_bram_addr),
        .user_bram_wdata(w_axi_bram_wdata), // 8bit
        .user_bram_we(w_axi_bram_we),
        .user_bram_rdata(w_axi_bram_rdata)  // 8bit
    );

    // [2] CNN Controller
    controller u_controller (
        .clk(s_axi_aclk),
        .rstn(s_axi_aresetn),
        .start(w_user_start),
        .done(w_user_done),
        .bram_addr(w_ctrl_bram_addr_full),
        .bram_wdata(w_ctrl_bram_wdata),
        .bram_we(w_ctrl_bram_we),
        .bram_en(w_ctrl_bram_en),
        .bram_rdata(w_ctrl_bram_rdata)
    );

    // [3] BRAM IP (True Dual Port)
    // *** Vivado IP 설정에서 Port A, Port B 모두 Width 8로 설정 필수 ***
    blk_mem_gen_0 u_bram (
        // Port A (AXI측)
        .clka(s_axi_aclk),
        .ena(1'b1),
        .wea(w_axi_bram_we),
        .addra(w_axi_bram_addr), // 16bit Addr
        .dina(w_axi_bram_wdata), // 8bit Data
        .douta(w_axi_bram_rdata),// 8bit Data

        // Port B (Controller측)
        .clkb(s_axi_aclk),
        .enb(w_ctrl_bram_en),
        .web(w_ctrl_bram_we),
        .addrb(w_ctrl_bram_addr_full[15:0]), 
        .dinb(w_ctrl_bram_wdata),
        .doutb(w_ctrl_bram_rdata)
    );

endmodule