`timescale 1ns / 1ps

module fc (
    input  wire        clk,
    input  wire        rstn,
    
    // Control Signals
    input  wire        start,      // 모듈 리셋 및 시작
    input  wire        valid,      // 입력 데이터 유효 (이미지 픽셀 & 가중치)
    output reg         done,       // 192개 계산 완료 신호
    
    // Data Inputs (From BRAM & Controller)
    input  wire [7:0]  pixel_in,   // 이미지 픽셀값 (Unsigned)
    input  wire signed [7:0] weight_in,  // 가중치 값 (Signed, BRAM에서 옴)
    
    // Result Output
    output reg  [7:0]  dout        // 최종 결과 (ReLU + Quantized)
);

    // =========================================================
    // Internal Registers & Wires
    // =========================================================
    
    // [1] Pipeline Stage 1: Multiplication
    // DSP 대신 LUT를 쓰라고 지시
    (* use_dsp = "no" *) reg signed [15:0] mult_reg;
    reg valid_d1; // valid 신호 1클럭 지연 (Stage 2용)

    // [2] Pipeline Stage 2: Accumulation
    // 24비트면 MNIST 연산에 충분 (32비트보다 가벼움)
    (* use_dsp = "no" *) reg signed [23:0] acc;
    reg [7:0] count; // 0 ~ 191 카운터

    // [3] Output Calculation
    reg signed [23:0] scaled_acc;

    // =========================================================
    // Main Logic
    // =========================================================
    always @(posedge clk) begin
        if (!rstn) begin
            // Reset
            mult_reg <= 0;
            valid_d1 <= 0;
            acc      <= 0;
            count    <= 0;
            done     <= 0;
            dout     <= 0;
        end else begin
            if (start) begin
                // Start 신호가 오면 누적기 초기화
                acc      <= 0;
                count    <= 0;
                done     <= 0;
                mult_reg <= 0;
                valid_d1 <= 0;
                dout     <= 0;
            end 
            else begin
                // -------------------------------------------------
                // Stage 1: Multiply (곱셈)
                // -------------------------------------------------
               if (valid) begin
        // Zero Sparsity: 입력이 0이면 곱셈 결과를 0으로 강제 (switching 감소 목적, 전력 효과는 미측정)
                    if (pixel_in == 0) begin
                         mult_reg <= 16'sd0;
                    end else begin
                         mult_reg <= $signed({1'b0, pixel_in}) * weight_in;
                    end
                end
                
                valid_d1 <= valid; // valid 신호 지연
            
                // -------------------------------------------------
                // Stage 2: Accumulate (누적) - 여기서 최적화!
                // -------------------------------------------------
                if (valid_d1) begin
                    // [수정] 곱셈 결과가 0이 아닐 때만 Adder 동작 및 레지스터 업데이트
                    // acc 레지스터의 Clock Enable(CE)로 합성되어 불필요한 갱신을 줄임 (Vivado 전력 추정상 유의미한 변화는 없었음)
                    if (mult_reg != 0) begin
                        acc <= acc + {{8{mult_reg[15]}}, mult_reg};
                    end
                    // mult_reg가 0이면 acc는 이전 값 유지 (Latch 아님, D-FF의 hold 기능)
            
                    // 카운터 및 완료 체크는 데이터 흐름(flow)에 따라가야 하므로 0이어도 진행해야 함
                    if (count == 191) begin
                        done <= 1;
                    end else begin
                        count <= count + 1;
                        done <= 0;
                    end
                end else begin
                    done <= 0;
                end 
                
                // -------------------------------------------------
                // Output Logic: Quantization & ReLU
                // -------------------------------------------------
                if (done) begin
                    // 1. Scaling (Shift) + Rounding (Bias 8)
                    // (값 + 8) >>> 4 : 나누기 16 + 반올림
                    scaled_acc = (acc + 8) >>> 4; 

                    // 2. Clamping (ReLU + 8bit Saturation)
                    if (scaled_acc < 0) begin
                        dout <= 8'd0;      // 음수 제거 (ReLU)
                    end else if (scaled_acc > 255) begin
                        dout <= 8'd255;    // 255 초과 제한
                    end else begin
                        dout <= scaled_acc[7:0]; // 정상 범위
                    end
                end
            end
        end
    end

endmodule