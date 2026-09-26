#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <stdint.h>
#include "platform.h"
#include "xparameters.h"
#include "xil_io.h"
#include "xil_types.h"
#include "xil_printf.h"

#include "cnn_common.h"   // Get_Global_Time, cycles_to_us, ps_forward_one, weights & test set


// ========================= User Config =========================
// 1) Base address of the custom IP (Block Design에서 확인해서 맞게 변경)
#define IP_BASEADDR             XPAR_TOP_0_BASEADDR   // TODO: xparameters.h 보고 실제 CNN IP BaseAddr로 수정

#define BRAM_DEPTH              4096U


#define REG_STATUS_OFFSET       0x14U    // slv_reg5
#define REG_CTRL_OFFSET         0x18U    // slv_reg6
#define BRAM_ADDR_REG_OFFSET    0x08U    // bram_addr_reg_addr = 'h8
#define BRAM_DATA_REG_OFFSET    0x0CU    // bram_data_reg_addr = 'hc

#define REG_STATUS  (IP_BASEADDR + REG_STATUS_OFFSET)
#define REG_CTRL    (IP_BASEADDR + REG_CTRL_OFFSET)
#define BRAM_ADDR_REG  (IP_BASEADDR + BRAM_ADDR_REG_OFFSET)
#define BRAM_DATA_REG  (IP_BASEADDR + BRAM_DATA_REG_OFFSET)


#define STAT_FC_DONE_MASK   (1u << 0)
#define STAT_C2_DONE_MASK   (1u << 1)
#define STAT_C1_DONE_MASK   (1u << 2)
#define STAT_P_DONE_MASK    (1u << 3)
#define STAT_DONE_MASK      (1u << 4)

#define CTRL_FC_WE_MASK     (1u << 0)
#define CTRL_C2_WE_MASK     (1u << 1)
#define CTRL_C1_WE_MASK     (1u << 2)
#define CTRL_IMG_WE_MASK    (1u << 3)
#define CTRL_WL_START_MASK  (1u << 4)
#define CTRL_START_MASK     (1u << 5)
#define CTRL_OD_ADDR_SHIFT  6
#define CTRL_CNN_RD_MASK    (1u << 10)


// ===================== BRAM Address Map (controller.v와 동일) =====================
#define ADDR_IMG       0x0000U   // 입력 이미지 28x28 (0~783)
#define ADDR_FC        0x0400U   // FC 결과(10바이트)
#define ADDR_WEIGHTS   0x0600U   // 가중치 시작 주소

// 가중치 개수는 배열 길이로 계산 
#define NUM_W_CONV1    (sizeof(conv1_w_embedded) / sizeof(conv1_w_embedded[0]))
#define NUM_W_CONV2    (sizeof(conv2_w_embedded) / sizeof(conv2_w_embedded[0]))
#define NUM_W_FC1      (sizeof(fc1_w_embedded)  / sizeof(fc1_w_embedded[0]))


// ===================== BRAM Access Helper 함수 =====================

// BRAM 시작 주소 설정
static inline void bram_set_addr(uint32_t bram_addr)
{
    // address counter 초기값 설정
    Xil_Out32(BRAM_ADDR_REG, (uint32_t)bram_addr);
}

// BRAM에 1바이트 write (주소는 내부에서 auto-increment)
static inline void bram_write_byte(uint8_t value)
{
    Xil_Out32(BRAM_DATA_REG, (uint32_t)value);
}

// BRAM에서 1바이트 read (주소는 내부에서 auto-increment)
static inline uint8_t bram_read_byte(void)
{
    return (uint8_t)Xil_In32(BRAM_DATA_REG);
}

// BRAM에 len 바이트 연속 write
static void bram_write_seq(uint32_t base_addr, const uint8_t *buf, int len)
{
    bram_set_addr(base_addr);
    for (int i = 0; i < len; ++i) {
        bram_write_byte(buf[i]);
    }
}

// BRAM에서 len 바이트 연속 read
static void bram_read_seq(uint32_t base_addr, uint8_t *buf, int len)
{
    bram_set_addr(base_addr);
    for (int i = 0; i < len; ++i) {
        buf[i] = bram_read_byte();
    }
}


// ===================== PL Weight Upload (PS->BRAM) =====================


static void pl_upload_weights_via_bram(void)
{
    // conv1 weights
    bram_write_seq(
        ADDR_WEIGHTS + 0,
        (const uint8_t *)conv1_w_embedded,
        (int)NUM_W_CONV1
    );

    // conv2 weights
    bram_write_seq(
        ADDR_WEIGHTS + (uint32_t)NUM_W_CONV1,
        (const uint8_t *)conv2_w_embedded,
        (int)NUM_W_CONV2
    );

    // fc1 weights
    bram_write_seq(
        ADDR_WEIGHTS + (uint32_t)(NUM_W_CONV1 + NUM_W_CONV2),
        (const uint8_t *)fc1_w_embedded,
        (int)NUM_W_FC1
    );
}


// ===================== PL 한 장 추론 =====================


static uint8_t pl_forward_one(const uint8_t *x_single)
{
    // 1) 이미지 BRAM에 쓰기
    bram_write_seq(ADDR_IMG, x_single, IMG_SIZE);

    // 2) START=1
    uint32_t ctrl = CTRL_START_MASK;
    Xil_Out32(REG_CTRL, ctrl);

    // 3) DONE=1 될 때까지 polling
    uint32_t stat;
    do {
        stat = Xil_In32(REG_STATUS);
    } while ((stat & STAT_DONE_MASK) == 0u);

    // 4) START=0 으로 내려서 controller가 IDLE로 돌아가게 함
    Xil_Out32(REG_CTRL, 0x00000000U);

    // 5) FC 결과 10바이트 읽기 (ADDR_FC ~ ADDR_FC+9)
    uint8_t logits_u8[FC_OUT];
    bram_read_seq(ADDR_FC, logits_u8, FC_OUT);

    // 6) Argmax
    int best_val   = (int)logits_u8[0];
    uint8_t best_i = 0;
    for (int i = 1; i < FC_OUT; ++i) {
        if ((int)logits_u8[i] > best_val) {
            best_val = (int)logits_u8[i];
            best_i   = (uint8_t)i;
        }
    }
    return best_i;
}


// ======================================================================
//                                main()
// ======================================================================

int main(void)
{
    init_platform();

    // Global Timer enable (cnn_common.h에서 사용하는 타이머)
    Xil_Out32(GTIMER_CONTROL_REG, 0x1);

    xil_printf("********************************************************\r\n");
    xil_printf("***         < SoC Design CNN Accelerator >            ***\r\n");
    xil_printf("***    PS vs PL LeNet-1-style CNN (MNIST, 1000 imgs)  ***\r\n");
    xil_printf("********************************************************\r\n");

    while (1) {
        xil_printf("\r\n>> Select Action\r\n");
        xil_printf("1. Run CNN test (PS vs PL)\r\n");
        xil_printf("2. Exit\r\n");
        xil_printf("Selection: ");

        char action_choice = inbyte();
        xil_printf("\r\n\r\n");

        switch (action_choice)
        {
        // =============================================================
        // 1) PS vs PL CNN 테스트
        // =============================================================
        case '1': {
            xil_printf("[RUN] CNN Test (PS vs PL), N_TEST = %d\r\n", N_TEST);

            // --------------------- PS PATH ----------------------
            xil_printf("[PS ] CNN running on ARM (C code)...\r\n");

            u64 t0_ps = Get_Global_Time();

            int correct_ps = 0;
            for (int i = 0; i < N_TEST; ++i) {
                const uint8_t *x     = &test_1000_images_embedded[i * IMG_SIZE];
                const uint8_t  label =  test_1000_labels_embedded[i];

                uint8_t pred = ps_forward_one(
                    x,
                    conv1_w_embedded,
                    conv2_w_embedded,
                    fc1_w_embedded
                );

                if (pred == label)
                    correct_ps++;
            }

            u64 t1_ps = Get_Global_Time();
            u64 cyc_ps = t1_ps - t0_ps;
            // cycles_to_us는 double을 반환하지만, 여기서는 정수 us로 캐스팅해서 사용
            u32 us_ps_total = (u32)cycles_to_us(cyc_ps);
            u32 us_ps_per   = us_ps_total / (u32)N_TEST;
            int acc_ps_pct  = (correct_ps * 100) / N_TEST;

            xil_printf("[PS ] Done. Acc = %d/%d = %d%% | Total = %u us | Avg/img = %u us\r\n",
                       correct_ps, N_TEST, acc_ps_pct,
                       (unsigned int)us_ps_total, (unsigned int)us_ps_per);

            // --------------------- PL WEIGHT LOAD ----------------
            xil_printf("[PL ] Loading weights to BRAM (ADDR 0x%04X)...\r\n", ADDR_WEIGHTS);

            u64 t0_w = Get_Global_Time();
            pl_upload_weights_via_bram();
            u64 t1_w = Get_Global_Time();
            u64 cyc_w = t1_w - t0_w;
            u32 us_pl_weight = (u32)cycles_to_us(cyc_w);

            xil_printf("[PL ] Weight upload done. Time = %u us\r\n", (unsigned int)us_pl_weight);

            // --------------------- PL PATH ----------------------
            xil_printf("[PL ] CNN running on accelerator (controller + PEs)...\r\n");

            u64 t0_pl = Get_Global_Time();

            int correct_pl = 0;
            for (int i = 0; i < N_TEST; ++i) {
                const uint8_t *x     = &test_1000_images_embedded[i * IMG_SIZE];
                const uint8_t  label =  test_1000_labels_embedded[i];

                uint8_t pred = pl_forward_one(x);

                if (pred == label)
                    correct_pl++;
            }

            u64 t1_pl = Get_Global_Time();
            u64 cyc_pl = t1_pl - t0_pl;
            u32 us_pl_total = (u32)cycles_to_us(cyc_pl);
            u32 us_pl_per   = us_pl_total / (u32)N_TEST;
            int acc_pl_pct  = (correct_pl * 100) / N_TEST;

            xil_printf("[PL ] Done. Acc = %d/%d = %d%% | Total (infer only) = %u us | Avg/img = %u us\r\n",
                       correct_pl, N_TEST, acc_pl_pct,
                       (unsigned int)us_pl_total, (unsigned int)us_pl_per);

            // --------------------- Summary ----------------------
            xil_printf("\r\n=== Summary (PS vs PL) ===\r\n");
            xil_printf("PS  : Acc = %d/%d = %d%% | Avg/img = %u us\r\n",
                       correct_ps, N_TEST, acc_ps_pct,
                       (unsigned int)us_ps_per);
            xil_printf("PL  : Acc = %d/%d = %d%% | Weight upload = %u us | Avg/img = %u us\r\n",
                       correct_pl, N_TEST, acc_pl_pct,
                       (unsigned int)us_pl_weight, (unsigned int)us_pl_per);

            if (us_pl_per > 0u) {
                // speedup을 소수 둘째자리까지 정수 연산으로 계산 (x.xx 배)
                u32 speedup_x100 = (us_ps_per * 100u) / us_pl_per;
                u32 speedup_int  = speedup_x100 / 100u;
                u32 speedup_frac = speedup_x100 % 100u;
                xil_printf("Speedup (PS / PL, steady-state) = %u.%02u x\r\n",
                           (unsigned int)speedup_int,
                           (unsigned int)speedup_frac);
            }

            break;
        }

        // =============================================================
        // 2) Exit
        // =============================================================
        case '2':
            xil_printf("Exit.\r\n");
            cleanup_platform();
            return 0;

        default:
            xil_printf("Invalid option. Please enter 1 or 2.\r\n");
            break;
        }
    }

    // (여기까지 오진 않겠지만 형식상)
    cleanup_platform();
    return 0;
}
