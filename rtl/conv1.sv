`timescale 1ns / 1ps

module conv1 (
    input  wire clk,
    input  wire rstn,
    
    // [Mode 1] 가중치 입력
    input  wire signed [7:0] kernel_in [0:3][0:24], 
   
    // [Mode 2] 연산 인터페이스
    input  wire        calc_start,      
    input  wire [7:0]  pixel_window [0:24], 

    // [Output] 결과 출력
    output wire        calc_done,       
    output wire [7:0]  dout_0,          
    output wire [7:0]  dout_1,          
    output wire [7:0]  dout_2,          
    output wire [7:0]  dout_3           
);

    // --- 1. MAC 인스턴스 (4개 병렬) ---
    wire signed [20:0] mac_out [0:3];
    
    // [수정] 모든 MAC의 done 신호를 받기 위한 4비트 와이어 선언
    wire [3:0] mac_dones; 
    wire mac_done_sig;

    // 0번 MAC의 done 신호만 대표로 사용 (어차피 동시에 끝나므로)
    assign mac_done_sig = mac_dones[0];

    genvar i;
    generate
        for(i=0; i<4; i=i+1) begin : MAC_ARRAY
            mac u_mac (
                .clk(clk),
                .rstn(rstn),
                .start(calc_start),
                .input_window(pixel_window),
                .kernel(kernel_in[i]),
                .done( mac_dones[i] ), // [수정] 배열의 각 비트에 1:1 연결
                .result(mac_out[i])
            );
        end
    endgenerate

    // --- 2. Quantization & ReLU (Output Logic) ---
    assign calc_done = mac_done_sig;

    function [7:0] quantize(input signed [20:0] val);
        reg [20:0] temp;
        begin
            if (val < 0) begin
                quantize = 8'd0; // ReLU
            end else begin
                temp = (val + 64) >>> 7; // Rounding & Scaling
                if (temp > 255) quantize = 8'd255; // Clamping
                else quantize = temp[7:0];
            end
        end
    endfunction

    assign dout_0 = quantize(mac_out[0]);
    assign dout_1 = quantize(mac_out[1]);
    assign dout_2 = quantize(mac_out[2]);
    assign dout_3 = quantize(mac_out[3]);

endmodule