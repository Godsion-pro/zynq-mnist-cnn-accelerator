`timescale 1ns / 1ps

module controller_1 (
    input  wire        clk,
    input  wire        rstn,
    input  wire        start,
    output reg         done,

    // BRAM Interface (Input Image)
    output reg  [15:0] bram_addr,
    output reg  [7:0]  bram_wdata = 0,
    output reg         bram_we,
    output reg         bram_en,
    input  wire [7:0]  bram_rdata
);

    // =================================================================
    // 1. 주소 상수 및 파라미터 정의
    // =================================================================
    localparam ADDR_IMG     = 16'h0000;
    localparam ADDR_FC      = 16'h1000;
    localparam ADDR_WEIGHTS = 16'h2000;
    
    // BRAM 읽기 레이턴시 (일반적으로 IP Core 설정에 따라 1 or 2)
    localparam LATENCY = 2; 

    // =================================================================
    // 2. 내부 저장소 및 연결
    // =================================================================
    reg signed [7:0] w_c1 [0:3][0:24]; 
    reg signed [7:0] w_c2 [0:11][0:3][0:24];

    // [CONV1]
    reg          c1_start;
    wire         c1_done;
    reg  [7:0]   c1_win [0:24];
    wire [7:0]   c1_dout [0:3];

    conv1 u_conv1 (
        .clk(clk), .rstn(rstn),
        .kernel_in(w_c1), 
        .calc_start(c1_start),
        .pixel_window(c1_win),
        .calc_done(c1_done),
        .dout_0(c1_dout[0]), .dout_1(c1_dout[1]),
        .dout_2(c1_dout[2]), .dout_3(c1_dout[3])
    );
    
    // BRAM Signals for C1
    reg  [11:0] c1_mem_addra, c1_mem_addrb;
    reg  [7:0]  c1_mem_wdata;
    wire [7:0]  c1_mem_rdata;
    reg         c1_mem_we, c1_mem_en;
    
    blk_mem_gen_conv1 u_mem_c1 (
        .clka(clk), .wea(c1_mem_we), .addra(c1_mem_addra), .dina(c1_mem_wdata),
        .clkb(clk), .enb(c1_mem_en), .addrb(c1_mem_addrb), .doutb(c1_mem_rdata)
    );
    
    // BRAM Signals for P1
    reg  [9:0]  p1_mem_addra, p1_mem_addrb;
    reg  [7:0]  p1_mem_wdata;
    wire [7:0]  p1_mem_rdata;
    reg         p1_mem_we, p1_mem_en;
    
    blk_mem_gen_p1 u_mem_p1 (
        .clka(clk), .wea(p1_mem_we), .addra(p1_mem_addra), .dina(p1_mem_wdata),
        .clkb(clk), .enb(p1_mem_en), .addrb(p1_mem_addrb), .doutb(p1_mem_rdata)
    );
    
    // BRAM Signals for C2
    reg  [9:0]  c2_mem_addra, c2_mem_addrb;
    reg  [7:0]  c2_mem_wdata;
    wire [7:0]  c2_mem_rdata;
    reg         c2_mem_we, c2_mem_en;
    
    blk_mem_gen_c2 u_mem_c2 (
        .clka(clk), .wea(c2_mem_we), .addra(c2_mem_addra), .dina(c2_mem_wdata),
        .clkb(clk), .enb(c2_mem_en), .addrb(c2_mem_addrb), .doutb(c2_mem_rdata)
    );

    // BRAM Signals for P2
    reg  [10:0] p2_mem_addra, p2_mem_addrb;
    reg  [7:0]  p2_mem_wdata;
    wire [7:0]  p2_mem_rdata;
    reg         p2_mem_we, p2_mem_en;
    
    blk_mem_gen_p2 u_mem_p2 (
        .clka(clk), .wea(p2_mem_we), .addra(p2_mem_addra), .dina(p2_mem_wdata),
        .clkb(clk), .enb(p2_mem_en), .addrb(p2_mem_addrb), .doutb(p2_mem_rdata)
    );

    // [CONV2]
    reg          c2_start;
    wire         c2_done;
    reg  [7:0]   c2_win [0:3][0:24];
    reg  [3:0]   c2_out_idx; 
    wire [7:0]   c2_dout_0, c2_dout_1;

    conv2 u_c2_0 (.clk(clk), .rstn(rstn), .calc_start(c2_start), .calc_done(c2_done), .pixel_window(c2_win), .kernel_in(w_c2[c2_out_idx + 0]), .dout(c2_dout_0));
    conv2 u_c2_1 (.clk(clk), .rstn(rstn), .calc_start(c2_start), .pixel_window(c2_win), .kernel_in(w_c2[c2_out_idx + 1]), .dout(c2_dout_1));

    // [POOLING]
    reg          pool_start;
    wire         pool_done;
    reg  [7:0]   pool_in [0:3];
    wire [7:0]   pool_dout;

    pool1 u_pool (.clk(clk), .rstn(rstn), .calc_start(pool_start), .val_in(pool_in), .calc_done(pool_done), .dout(pool_dout));

    // [FC] Interface
    wire [10:0] fc_bram_addr;
    wire [7:0]  fc_bram_din;
    wire [7:0]  fc_bram_dout;
    wire        fc_bram_we;
    
    blk_mem_gen_1 u_bram_fc (
        .clka(clk), .wea(fc_bram_we), .addra(fc_bram_addr), .dina(fc_bram_din), .douta(fc_bram_dout)
    );

    reg         fc_start, fc_valid;
    wire        fc_done;
    wire [7:0]  fc_result;

    fc u_fc (
        .clk(clk), .rstn(rstn), .start(fc_start), .valid(fc_valid),
        .pixel_in(p2_mem_rdata), .weight_in(fc_bram_dout),
        .done(fc_done), .dout(fc_result)
    );

    // =================================================================
    // 4. FSM (Pipelined)
    // =================================================================
    typedef enum logic [5:0] {
        IDLE, 
        // --- Weight Load (Pipelined) ---
        LOAD_W_STREAM,
        
        // --- CONV1 (Burst Read Window) ---
        C1_INIT, C1_BURST_RD, C1_CALC, C1_WR, C1_NEXT,
        
        // --- POOL1 (Burst Read Window) ---
        P1_INIT, P1_BURST_RD, P1_CALC, P1_WR, P1_NEXT,
        
        // --- CONV2 (Burst Read Window) ---
        C2_INIT, C2_BURST_RD, C2_CALC_CH, C2_WR, C2_NEXT,
        
        // --- POOL2 (Burst Read Window) ---
        P2_INIT, P2_BURST_RD, P2_CALC, P2_WR, P2_NEXT,
        
        // --- FC (Fully Pipelined MAC) ---
        FC_INIT, FC_STREAM_MAC, FC_WAIT_RESULT, FC_WR, 
        
        DONE
    } state_t;
    
    state_t state;
    
    // Counters
    reg [11:0] w_cnt_req, w_cnt_ack; // 가중치 읽기/쓰기 카운터 분리
    reg        weights_loaded;
    
    reg [7:0] idx_out, idx_in, idx_k;
    reg [4:0] row, col, kr, kc;
    reg [3:0] ch, sub_ch; 
    
    // Burst Read Counters
    reg [4:0] burst_cnt_req; // 0 to 24 (for 5x5 window)
    reg [4:0] burst_cnt_ack;
    
    // FC Pipelining
    reg [7:0] col_fc_req; // 0 to 191
    reg [7:0] col_fc_ack;

    // FC Logic Binding
    assign fc_bram_we   = (state == LOAD_W_STREAM && w_cnt_ack >= 1300 && w_cnt_ack < 3220); // Ack 시점에 쓰기
    assign fc_bram_din  = bram_rdata;
    
    // FC 주소 MUX: 로딩 중일 때는 w_cnt 기반, 계산 중일 때는 row/col 기반
    assign fc_bram_addr = (state == LOAD_W_STREAM) ? (w_cnt_ack - 1300) : 
                          (state == FC_STREAM_MAC) ? (row * 192 + col_fc_req) : 0;

    always @(posedge clk or negedge rstn) begin
        if(!rstn) begin
            state <= IDLE; done <= 0;
            bram_en <= 0; bram_we <= 0;
            c1_mem_en <= 0; c1_mem_we <= 0;
            p1_mem_en <= 0; p1_mem_we <= 0;
            c2_mem_en <= 0; c2_mem_we <= 0;
            p2_mem_en <= 0; p2_mem_we <= 0;
            c1_start<=0; c2_start<=0; pool_start<=0; fc_start<=0; fc_valid<=0;
            bram_addr<=0; bram_wdata<=0; 
            weights_loaded <= 1'b0;
            w_cnt_req <= 0; w_cnt_ack <= 0;
        end else begin
            case(state)
                IDLE: begin
                    done <= 0;
                    if (start) begin
                        if (!weights_loaded) begin
                            w_cnt_req <= 0; w_cnt_ack <= 0;
                            idx_out <= 0; idx_in <= 0; idx_k <= 0;
                            state <= LOAD_W_STREAM;
                        end else begin
                            state <= C1_INIT;
                        end
                    end
                end

                // ----------------------------------------------------------------
                // [Pipelined Weight Loading]
                // Request는 매 클럭 계속 주소를 쏘고, Ack는 데이터가 오면 저장
                // ----------------------------------------------------------------
                LOAD_W_STREAM: begin
                    // 1. Request Stage (Address Gen)
                    if (w_cnt_req < 3220) begin
                        bram_en <= 1; bram_we <= 0;
                        bram_addr <= ADDR_WEIGHTS + w_cnt_req;
                        w_cnt_req <= w_cnt_req + 1;
                    end else begin
                        bram_en <= 0; // 요청 끝
                    end

                    // 2. Acknowledge Stage (Data Save) - Latency 고려
                    // w_cnt_ack는 유효한 데이터가 도착했음을 의미하는 카운터
                    // Request가 시작된 후 LATENCY만큼 지나야 Ack 동작 시작
                    if (w_cnt_ack < 3220) begin
                        // 간단한 파이프라인 정합: Req와 Ack의 차이가 LATENCY 이상 벌어지거나 Req가 끝났을 때
                        // 여기서는 단순히 카운터 기반으로 데이터가 유효하다고 가정 (BRAM 특성)
                        if (w_cnt_req > w_cnt_ack + (LATENCY-1) || (w_cnt_req == 3220 && w_cnt_ack < 3220)) begin
                            // w_cnt_ack 값에 따라 데이터 분류 저장 (로직은 기존과 동일하되 ack 기준)
                            
                            // [1] Load CONV1 (0 ~ 99)
                            if (w_cnt_ack < 100) begin
                                w_c1[idx_out][idx_k] <= bram_rdata;
                                if (w_cnt_ack == 99) begin
                                    idx_out <= 0; idx_in <= 0; idx_k <= 0;
                                end else begin
                                    if (idx_k == 24) begin
                                        idx_k <= 0; idx_out <= idx_out + 1;
                                    end else idx_k <= idx_k + 1;
                                end
                            end 
                            // [2] Load CONV2 (100 ~ 1299)
                            else if (w_cnt_ack < 1300) begin
                                w_c2[idx_out][idx_in][idx_k] <= bram_rdata;
                                if (w_cnt_ack == 1299) begin
                                    idx_out <= 0; idx_in <= 0;
                                end else begin
                                    if (idx_k == 24) begin
                                        idx_k <= 0;
                                        if (idx_in == 3) begin
                                            idx_in <= 0; idx_out <= idx_out + 1;
                                        end else idx_in <= idx_in + 1;
                                    end else idx_k <= idx_k + 1;
                                end
                            end 
                            // [3] Load FC (1300 ~ 3219) - assign문에서 처리 (fc_bram_we)
                            else begin
                                // 인덱스 관리만 수행
                                if (idx_in == 191) begin
                                    idx_in <= 0; idx_out <= idx_out + 1;
                                end else idx_in <= idx_in + 1;
                            end

                            w_cnt_ack <= w_cnt_ack + 1;
                        end
                    end else begin
                        // 모든 데이터 수신 완료
                        weights_loaded <= 1'b1;
                        state <= C1_INIT;
                    end
                end

                // ----------------------------------------------------------------
                // CONV1: Burst Window Read
                // ----------------------------------------------------------------
                C1_INIT: begin row<=0; col<=0; state<=C1_BURST_RD; burst_cnt_req<=0; burst_cnt_ack<=0; end
                
                C1_BURST_RD: begin
                    // 1. Burst Request (25 cycles continuous)
                    if (burst_cnt_req < 25) begin
                        bram_en <= 1; bram_we <= 0;
                        // burst_cnt_req를 5로 나누어 kr, kc 계산 (합성기가 최적화함)
                        // kr = burst_cnt_req / 5, kc = burst_cnt_req % 5
                        bram_addr <= ADDR_IMG + (row + (burst_cnt_req/5))*28 + (col + (burst_cnt_req%5));
                        burst_cnt_req <= burst_cnt_req + 1;
                    end else begin
                         bram_en <= 0;
                    end

                    // 2. Burst Data Capture
                    if (burst_cnt_ack < 25) begin
                        // Wait for Latency
                        if (burst_cnt_req > burst_cnt_ack + (LATENCY-1) || (burst_cnt_req==25)) begin
                            c1_win[burst_cnt_ack] <= bram_rdata;
                            burst_cnt_ack <= burst_cnt_ack + 1;
                        end
                    end else begin
                        state <= C1_CALC;
                    end
                end

                C1_CALC: begin c1_start<=1; state<=C1_WR; sub_ch<=0; end
                C1_WR: begin
                    c1_start<=0;
                    if (sub_ch == 0) begin
                        if (c1_done) begin
                           c1_mem_we<=1; c1_mem_en<=1;
                           c1_mem_addra <= (sub_ch*576) + (row*24) + col;
                           c1_mem_wdata <= c1_dout[0];
                           sub_ch <= 1;
                        end
                    end else begin
                        c1_mem_we<=1; c1_mem_en<=1;
                        c1_mem_addra <= (sub_ch*576) + (row*24) + col;
                        case(sub_ch)
                            1: c1_mem_wdata <= c1_dout[1];
                            2: c1_mem_wdata <= c1_dout[2];
                            3: c1_mem_wdata <= c1_dout[3];
                        endcase
                        if (sub_ch < 3) sub_ch <= sub_ch + 1;
                        else begin
                            state <= C1_NEXT;
                        end
                    end
                end
                C1_NEXT: begin
                    c1_mem_we<=0; c1_mem_en<=0;
                    if(col<23) begin col<=col+1; state<=C1_BURST_RD; burst_cnt_req<=0; burst_cnt_ack<=0; end
                    else if(row<23) begin col<=0; row<=row+1; state<=C1_BURST_RD; burst_cnt_req<=0; burst_cnt_ack<=0; end
                    else state <= P1_INIT;
                end

                // ----------------------------------------------------------------
                // POOL1: Burst Read (2x2 = 4 cycles)
                // ----------------------------------------------------------------
                P1_INIT: begin ch<=0; row<=0; col<=0; state<=P1_BURST_RD; burst_cnt_req<=0; burst_cnt_ack<=0; end
                
                P1_BURST_RD: begin
                     // Request 4 pixels (0, 1, 2, 3 -> (0,0), (0,1), (1,0), (1,1))
                     if(burst_cnt_req < 4) begin
                         c1_mem_en<=1; c1_mem_we<=0;
                         // Mapping req 0->(0,0), 1->(0,1), 2->(1,0), 3->(1,1)
                         c1_mem_addrb <= (ch*576) + ((row + (burst_cnt_req/2))*24) + (col + (burst_cnt_req%2));
                         burst_cnt_req <= burst_cnt_req + 1;
                     end else c1_mem_en<=0;

                     if(burst_cnt_ack < 4) begin
                         if (burst_cnt_req > burst_cnt_ack + (LATENCY-1) || burst_cnt_req==4) begin
                             pool_in[burst_cnt_ack] <= c1_mem_rdata;
                             burst_cnt_ack <= burst_cnt_ack + 1;
                         end
                     end else state <= P1_CALC;
                end

                P1_CALC: begin pool_start<=1; state<=P1_WR; end
                P1_WR: begin
                    pool_start<=0;
                    if(pool_done) begin
                        p1_mem_en<=1; p1_mem_we<=1;
                        p1_mem_addra <= (ch*144) + ((row>>1)*12) + (col>>1);
                        p1_mem_wdata <= {24'd0, pool_dout};
                        state <= P1_NEXT;
                    end
                end
                P1_NEXT: begin
                    p1_mem_we<=0; p1_mem_en<=0;
                    if(col<22) begin col<=col+2; state<=P1_BURST_RD; burst_cnt_req<=0; burst_cnt_ack<=0; end
                    else if(row<22) begin col<=0; row<=row+2; state<=P1_BURST_RD; burst_cnt_req<=0; burst_cnt_ack<=0; end
                    else if(ch<3) begin col<=0; row<=0; ch<=ch+1; state<=P1_BURST_RD; burst_cnt_req<=0; burst_cnt_ack<=0; end
                    else state <= C2_INIT;
                end

                // ----------------------------------------------------------------
                // CONV2: Burst Read (Sub_ch loop is inside)
                // ----------------------------------------------------------------
                C2_INIT: begin row<=0; col<=0; sub_ch<=0; state<=C2_BURST_RD; burst_cnt_req<=0; burst_cnt_ack<=0; end
                
                C2_BURST_RD: begin
                    // Load 5x5 window for current sub_ch
                    if (burst_cnt_req < 25) begin
                        p1_mem_en<=1;
                        p1_mem_addrb <= (sub_ch*144) + (row+(burst_cnt_req/5))*12 + (col+(burst_cnt_req%5));
                        burst_cnt_req <= burst_cnt_req + 1;
                    end else p1_mem_en <= 0;

                    if (burst_cnt_ack < 25) begin
                        if (burst_cnt_req > burst_cnt_ack + (LATENCY-1) || burst_cnt_req==25) begin
                            c2_win[sub_ch][burst_cnt_ack] <= p1_mem_rdata[7:0];
                            burst_cnt_ack <= burst_cnt_ack + 1;
                        end
                    end else begin
                        // 1개 채널 로딩 끝
                        if (sub_ch < 3) begin
                            sub_ch <= sub_ch + 1;
                            burst_cnt_req <= 0;
                            burst_cnt_ack <= 0;
                            // Stay in C2_BURST_RD
                        end else begin
                            state <= C2_CALC_CH;
                            c2_out_idx <= 0;
                        end
                    end
                end
                
                C2_CALC_CH: begin
                    c2_start <= 1; state <= C2_WR; sub_ch <= 0;
                end
                
                C2_WR: begin
                    c2_start <= 0;
                    if(sub_ch == 0) begin
                        if(c2_done) begin
                            bram_en<=1; c2_mem_we<=1; c2_mem_en<=1;
                            c2_mem_addra <= ((c2_out_idx + 0) * 64) + (row*8) + col;
                            c2_mem_wdata<= c2_dout_0;
                            sub_ch <= 1;
                        end
                    end else begin
                        bram_en<=1; c2_mem_we<=1; c2_mem_en<=1;
                        c2_mem_addra <= ((c2_out_idx + 1) * 64) + (row*8) + col;
                        c2_mem_wdata<= c2_dout_1;
                        
                        if (c2_out_idx < 10) begin
                            c2_out_idx <= c2_out_idx + 2;
                            sub_ch <= 0;
                            state <= C2_CALC_CH;
                        end else begin
                            sub_ch <= 0; c2_mem_we<=0; c2_mem_en<=0;
                            state <= C2_NEXT;
                        end
                    end
                end
                C2_NEXT: begin
                    if(col<7) begin col<=col+1; sub_ch<=0; state<=C2_BURST_RD; burst_cnt_req<=0; burst_cnt_ack<=0; end
                    else if(row<7) begin col<=0; row<=row+1; sub_ch<=0; state<=C2_BURST_RD; burst_cnt_req<=0; burst_cnt_ack<=0; end
                    else state <= P2_INIT;
                end

                // ----------------------------------------------------------------
                // POOL2: Burst Read
                // ----------------------------------------------------------------
                P2_INIT: begin ch<=0; row<=0; col<=0; state<=P2_BURST_RD; burst_cnt_req<=0; burst_cnt_ack<=0; end
                P2_BURST_RD: begin
                    if(burst_cnt_req < 4) begin
                        c2_mem_en<=1; c2_mem_we<=0;
                        c2_mem_addrb <= (ch*64) + ((row + burst_cnt_req/2)*8) + (col + burst_cnt_req%2);
                        burst_cnt_req <= burst_cnt_req + 1;
                    end else c2_mem_en<=0;
                    
                    if(burst_cnt_ack < 4) begin
                        if(burst_cnt_req > burst_cnt_ack + (LATENCY-1) || burst_cnt_req==4) begin
                            pool_in[burst_cnt_ack] <= c2_mem_rdata;
                            burst_cnt_ack <= burst_cnt_ack + 1;
                        end
                    end else state <= P2_CALC;
                end
                P2_CALC: begin pool_start<=1; state<=P2_WR; end
                P2_WR: begin
                    pool_start<=0;
                    if(pool_done) begin
                        p2_mem_en<=1; p2_mem_we<=1;
                        p2_mem_addra <= (ch*16) + ((row>>1)*4) + (col>>1);
                        p2_mem_wdata <= {24'd0, pool_dout};
                        state <= P2_NEXT;
                    end
                end
                P2_NEXT: begin
                    p2_mem_we<=0; p2_mem_en<=0;
                    if(col<6) begin col<=col+2; state<=P2_BURST_RD; burst_cnt_req<=0; burst_cnt_ack<=0; end
                    else if(row<6) begin col<=0; row<=row+2; state<=P2_BURST_RD; burst_cnt_req<=0; burst_cnt_ack<=0; end
                    else if(ch<11) begin col<=0; row<=0; ch<=ch+1; state<=P2_BURST_RD; burst_cnt_req<=0; burst_cnt_ack<=0; end
                    else state <= FC_INIT;
                end

                // ----------------------------------------------------------------
                // FC: Fully Pipelined MAC
                // 192번의 곱셈을 연속 스트림으로 처리
                // ----------------------------------------------------------------
                FC_INIT: begin 
                    row <= 0; // Class Index (0~9)
                    fc_start <= 1; // Reset FC Accumulator
                    col_fc_req <= 0; col_fc_ack <= 0;
                    state <= FC_STREAM_MAC; 
                end
                
                FC_STREAM_MAC: begin
                    fc_start <= 0;
                    fc_valid <= 0; // Default off
                    
                    // 1. Stream Request
                    if (col_fc_req < 192) begin
                        p2_mem_en <= 1; p2_mem_we <= 0;
                        p2_mem_addrb <= col_fc_req; // assign문에 의해 주소 연결됨 (0~191)
                        // BRAM FC Weight 주소도 assign문에 의해 자동 매핑됨
                        col_fc_req <= col_fc_req + 1;
                    end else begin
                        p2_mem_en <= 0;
                    end

                    // 2. Stream Data Valid (Ack)
                    if (col_fc_ack < 192) begin
                        if (col_fc_req > col_fc_ack + (LATENCY-1) || col_fc_req == 192) begin
                            // 데이터가 도착한 시점
                            fc_valid <= 1; // FC 모듈에게 "이 데이터 유효해, 계산해" 신호
                            col_fc_ack <= col_fc_ack + 1;
                        end
                    end else begin
                        // 192개 데이터 전송 완료 -> 결과 대기
                        state <= FC_WAIT_RESULT;
                    end
                end
                
                FC_WAIT_RESULT: begin
                    fc_valid <= 0;
                    if (fc_done) begin
                        state <= FC_WR;
                    end
                end
                
                FC_WR: begin
                    bram_en <= 1; bram_we <= 1;
                    bram_addr <= ADDR_FC + row;
                    bram_wdata <= fc_result;
                    
                    if (row < 9) begin
                        row <= row + 1;
                        fc_start <= 1; // Reset FC for next class
                        col_fc_req <= 0; col_fc_ack <= 0;
                        state <= FC_STREAM_MAC;
                    end else begin
                        state <= DONE;
                    end
                end

                DONE: begin
                    done <= 1; bram_en<=0; bram_we<=0;
                    if(!start) state <= IDLE;
                end
            endcase
        end
    end

endmodule