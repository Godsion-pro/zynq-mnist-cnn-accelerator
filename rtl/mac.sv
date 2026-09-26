`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/11/18 22:43:09
// Design Name: 
// Module Name: mac
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module mac (
    input  wire clk,
    input  wire rstn,
    input  wire start, // 계산 시작 펄스

    // 5x5 입력 (외부에서 병렬로 들어옴)
    input  wire [7:0] input_window [0:24],       // Unsigned Image
    input  wire signed [7:0] kernel [0:24],      // Signed Weight

    output wire done,                            // 계산 완료 펄스
    output wire signed [20:0] result             // 결과값
);

    // Pipeline Stage 0: 곱셈
    reg signed [15:0] mul_res [0:24];
    integer i;
    always @(posedge clk) begin
        if (start) begin
            for(i=0; i<25; i=i+1) begin
                // {0, input}으로 unsigned를 양수로 만들고 signed 커널과 곱함
                if (input_window[i]==0) mul_res[i]<=0;
                else mul_res[i] <= $signed({1'b0, input_window[i]}) * kernel[i];
            end
        end
    end

    // Pipeline Stage 1~5: Adder Tree (이전 코드와 동일)
    reg signed [16:0] add1 [0:12];
    reg signed [17:0] add2 [0:6];
    reg signed [18:0] add3 [0:3];
    reg signed [19:0] add4 [0:1];
    reg signed [20:0] final_res;

    always @(posedge clk) begin
        // Stg 1
        add1[0]<=mul_res[0]+mul_res[1];   add1[1]<=mul_res[2]+mul_res[3];
        add1[2]<=mul_res[4]+mul_res[5];   add1[3]<=mul_res[6]+mul_res[7];
        add1[4]<=mul_res[8]+mul_res[9];   add1[5]<=mul_res[10]+mul_res[11];
        add1[6]<=mul_res[12]+mul_res[13]; add1[7]<=mul_res[14]+mul_res[15];
        add1[8]<=mul_res[16]+mul_res[17]; add1[9]<=mul_res[18]+mul_res[19];
        add1[10]<=mul_res[20]+mul_res[21];add1[11]<=mul_res[22]+mul_res[23];
        add1[12]<=mul_res[24];

        // Stg 2
        add2[0]<=add1[0]+add1[1]; add2[1]<=add1[2]+add1[3];
        add2[2]<=add1[4]+add1[5]; add2[3]<=add1[6]+add1[7];
        add2[4]<=add1[8]+add1[9]; add2[5]<=add1[10]+add1[11];
        add2[6]<=add1[12];

        // Stg 3
        add3[0]<=add2[0]+add2[1]; add3[1]<=add2[2]+add2[3];
        add3[2]<=add2[4]+add2[5]; add3[3]<=add2[6];

        // Stg 4
        add4[0]<=add3[0]+add3[1]; add4[1]<=add3[2]+add3[3];

        // Stg 5
        final_res <= add4[0] + add4[1];
    end

    assign result = final_res;

    // Delay done signal (Latency 6 cycles)
    reg [5:0] shift_reg;
    always @(posedge clk) begin
        if(!rstn) shift_reg <= 0;
        else shift_reg <= {shift_reg[4:0], start};
    end
    assign done = shift_reg[5];

endmodule