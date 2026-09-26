`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: pool1
// Description: 2x2 Max Pooling Unit
//              4개의 픽셀 입력 -> 1개의 Max값 출력
//              (각 채널별로 순차적으로 사용)
//////////////////////////////////////////////////////////////////////////////////

module pool1 (
    input  wire clk,
    input  wire rstn,

    // [Control]
    input  wire        calc_start,     // 연산 시작 신호
    
    // [Data Input] 2x2 Window (4 pixels)
    // Controller에서 (r,c), (r,c+1), (r+1,c), (r+1,c+1) 값을 읽어서 넣어줌
    input  wire [7:0]  val_in [0:3],   
    
    // [Data Output]
    output reg         calc_done,      // 결과 유효 신호 (1 cycle delayed)
    output reg  [7:0]  dout            // Max Value
);

    // 비교 로직은 Combinational로 처리하고, 결과만 레지스터에 저장합니다.
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            dout <= 8'd0;
            calc_done <= 1'b0;
        end else begin
            if (calc_start) begin
                // 2x2 Max Tree 구조
                // Stage 1: 2쌍 비교
                reg [7:0] max_01, max_23;
                
                max_01 = (val_in[0] > val_in[1]) ? val_in[0] : val_in[1];
                max_23 = (val_in[2] > val_in[3]) ? val_in[2] : val_in[3];
                
                // Stage 2: 최종 비교
                dout <= (max_01 > max_23) ? max_01 : max_23;
                
                calc_done <= 1'b1; // 1클럭 후에 완료
            end else begin
                calc_done <= 1'b0; // Handshake용 펄스
            end
        end
    end

endmodule