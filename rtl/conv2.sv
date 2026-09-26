`timescale 1ns / 1ps

module conv2 (
    input  wire clk,
    input  wire rstn,

    // [Control]
    input  wire        calc_start,
    output wire        calc_done,

    // [Input Data] 4개 채널 윈도우
    input  wire [7:0]  pixel_window [0:3][0:24],

    // [Weights] 4개 채널 커널
    input  wire signed [7:0] kernel_in [0:3][0:24],

    // [Output]
    output wire [7:0]  dout
);

    // --- 1. MAC 연산 (4 Input Channels Parallel) ---
    wire signed [20:0] mac_results [0:3];
    
    // [수정] done 신호 연결을 위한 와이어 배열
    wire [3:0] mac_dones;
    wire mac_done_sig;

    // 0번 채널의 완료 신호를 대표로 사용
    assign mac_done_sig = mac_dones[0];

    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) begin : MAC_4CH
            mac_dsp u_mac (
                .clk(clk),
                .rstn(rstn),
                .start(calc_start),
                .input_window(pixel_window[i]), 
                .kernel(kernel_in[i]),          
                .done( mac_dones[i] ), // [수정] 조건문 제거하고 직접 연결
                .result(mac_results[i])
            );
        end
    endgenerate

    // --- 2. 채널 합산 (Channel Summation) ---
    reg signed [22:0] sum_result;
    reg sum_valid;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            sum_result <= 0;
            sum_valid <= 0;
        end else begin
            if (mac_done_sig) begin
                // 4개 채널 합산
                sum_result <= mac_results[0] + mac_results[1] + mac_results[2] + mac_results[3];
                sum_valid <= 1'b1;
            end else begin
                sum_valid <= 1'b0;
            end
        end
    end

    // --- 3. Quantization & ReLU ---
    assign calc_done = sum_valid;

    function [7:0] quantize(input signed [22:0] val);
        reg [22:0] temp;
        begin
            if (val < 0) begin
                quantize = 8'd0; // ReLU
            end else begin
                temp = (val + 64) >>> 7; 
                if (temp > 255) quantize = 8'd255;
                else quantize = temp[7:0];
            end
        end
    endfunction

    assign dout = quantize(sum_result);

endmodule