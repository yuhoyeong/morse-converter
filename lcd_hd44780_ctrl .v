// 50MHz 기준 HD44780(텍스트 LCD) 컨트롤러
// - 8bit 모드
// - 전원 후 초기화 시퀀스 자동 실행
// - char_valid가 1일 때 char_in(ASCII)을 LCD에 한 글자씩 써줌
// - RS/RW/E, D0~D7 직접 제어
module lcd_hd44780_ctrl (
    input  wire       clk,         // 50MHz
    input  wire       rst_n,       // active-low

    input  wire [7:0] char_in,     // 쓸 문자 (ASCII)
    input  wire       char_valid,  // 1 클럭 펄스: 새로운 문자 요청

    output reg        ready,       // 1이면 새 문자 받기 가능 (초기화 끝 + idle)

    // Text LCD 핀
    output reg        TLCD_D0,
    output reg        TLCD_D1,
    output reg        TLCD_D2,
    output reg        TLCD_D3,
    output reg        TLCD_D4,
    output reg        TLCD_D5,
    output reg        TLCD_D6,
    output reg        TLCD_D7,
    output reg        TLCD_RS,
    output reg        TLCD_RW,
    output reg        TLCD_E
);

    //==========================================================
    // 파라미터 (50MHz 기준 타이밍)
    //==========================================================
    parameter integer CLK_FREQ      = 50_000_000;
    // 전원 후 대기시간 >40ms -> 50ms 사용
    parameter integer PWR_ON_WAIT   = CLK_FREQ / 20;       // 0.05s = 2_500_000
    // 일반 명령/데이터 실행시간 >40us -> 60us 사용
    parameter integer CMD_WAIT_CYC  = 60 * (CLK_FREQ / 1_000_000);   // 60us
    // Clear/Return Home 명령 >1.64ms -> 2ms 사용
    parameter integer CLR_WAIT_CYC  = 2  * (CLK_FREQ / 1_000);       // 2ms
    // E 펄스 폭: >450ns -> 약 1us 정도 (50클럭)
    parameter integer E_PULSE_CYC   = (CLK_FREQ / 1_000_000);        // 1us

    //==========================================================
    // 내부 상태 정의
    //==========================================================
    localparam S_PWR_WAIT          = 4'd0;
    localparam S_INIT_FUNC_SET     = 4'd1;
    localparam S_INIT_FUNC_WAIT    = 4'd2;
    localparam S_INIT_DISP_OFF     = 4'd3;
    localparam S_INIT_DISP_OFF_WAIT= 4'd4;
    localparam S_INIT_CLEAR        = 4'd5;
    localparam S_INIT_CLEAR_WAIT   = 4'd6;
    localparam S_INIT_ENTRY_MODE   = 4'd7;
    localparam S_INIT_ENTRY_WAIT   = 4'd8;
    localparam S_INIT_DISP_ON      = 4'd9;
    localparam S_INIT_DISP_ON_WAIT = 4'd10;
    localparam S_IDLE              = 4'd11;
    localparam S_WRITE_DATA        = 4'd12;
    localparam S_WRITE_DATA_WAIT   = 4'd13;

    reg [3:0]  state;
    reg [21:0] wait_cnt;      // 최대 PWR_ON_WAIT까지 커버
    reg [7:0]  data_reg;      // LCD 버스에 나갈 데이터
    reg        rs_reg;        // RS 값 버퍼
    reg        rw_reg;        // RW 값 버퍼

    //==========================================================
    // LCD 데이터 버스에 data_reg 반영
    //==========================================================
    always @(*) begin
        TLCD_D0 = data_reg[0];
        TLCD_D1 = data_reg[1];
        TLCD_D2 = data_reg[2];
        TLCD_D3 = data_reg[3];
        TLCD_D4 = data_reg[4];
        TLCD_D5 = data_reg[5];
        TLCD_D6 = data_reg[6];
        TLCD_D7 = data_reg[7];

        TLCD_RS = rs_reg;
        TLCD_RW = rw_reg;
    end

    //==========================================================
    // 메인 FSM
    //==========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= S_PWR_WAIT;
            wait_cnt <= 22'd0;

            data_reg <= 8'd0;
            rs_reg   <= 1'b0;
            rw_reg   <= 1'b0;
            TLCD_E   <= 1'b0;
            ready    <= 1'b0;
        end else begin
            case (state)
                //--------------------------------------------------
                // 전원 안정화 대기
                //--------------------------------------------------
                S_PWR_WAIT: begin
                    ready <= 1'b0;
                    TLCD_E <= 1'b0;
                    if (wait_cnt < PWR_ON_WAIT-1) begin
                        wait_cnt <= wait_cnt + 1'b1;
                    end else begin
                        wait_cnt <= 22'd0;
                        // Function Set: 8bit, 2line, 5x8 dots (0x38)
                        data_reg <= 8'h38;
                        rs_reg   <= 1'b0;   // command
                        rw_reg   <= 1'b0;   // write
                        TLCD_E   <= 1'b1;   // E high 시작
                        state    <= S_INIT_FUNC_WAIT;
                    end
                end

                //--------------------------------------------------
                // Function Set 대기
                //--------------------------------------------------
                S_INIT_FUNC_WAIT: begin
                    wait_cnt <= wait_cnt + 1'b1;
                    // E펄스 끝내기
                    if (wait_cnt == E_PULSE_CYC-1)
                        TLCD_E <= 1'b0;

                    if (wait_cnt >= CMD_WAIT_CYC-1) begin
                        wait_cnt <= 22'd0;
                        // Display OFF (0x08)
                        data_reg <= 8'h08;
                        rs_reg   <= 1'b0;
                        rw_reg   <= 1'b0;
                        TLCD_E   <= 1'b1;
                        state    <= S_INIT_DISP_OFF_WAIT;
                    end
                end

                //--------------------------------------------------
                // Display OFF 대기
                //--------------------------------------------------
                S_INIT_DISP_OFF_WAIT: begin
                    wait_cnt <= wait_cnt + 1'b1;
                    if (wait_cnt == E_PULSE_CYC-1)
                        TLCD_E <= 1'b0;

                    if (wait_cnt >= CMD_WAIT_CYC-1) begin
                        wait_cnt <= 22'd0;
                        // Clear Display (0x01)
                        data_reg <= 8'h01;
                        rs_reg   <= 1'b0;
                        rw_reg   <= 1'b0;
                        TLCD_E   <= 1'b1;
                        state    <= S_INIT_CLEAR_WAIT;
                    end
                end

                //--------------------------------------------------
                // Clear Display 대기 (긴 시간 필요)
                //--------------------------------------------------
                S_INIT_CLEAR_WAIT: begin
                    wait_cnt <= wait_cnt + 1'b1;
                    if (wait_cnt == E_PULSE_CYC-1)
                        TLCD_E <= 1'b0;

                    if (wait_cnt >= CLR_WAIT_CYC-1) begin
                        wait_cnt <= 22'd0;
                        // Entry Mode Set: I/D=1, S=0  (0x06)
                        data_reg <= 8'h06;
                        rs_reg   <= 1'b0;
                        rw_reg   <= 1'b0;
                        TLCD_E   <= 1'b1;
                        state    <= S_INIT_ENTRY_WAIT;
                    end
                end

                //--------------------------------------------------
                // Entry Mode 대기
                //--------------------------------------------------
                S_INIT_ENTRY_WAIT: begin
                    wait_cnt <= wait_cnt + 1'b1;
                    if (wait_cnt == E_PULSE_CYC-1)
                        TLCD_E <= 1'b0;

                    if (wait_cnt >= CMD_WAIT_CYC-1) begin
                        wait_cnt <= 22'd0;
                        // Display ON, Cursor OFF, Blink OFF (0x0C)
                        data_reg <= 8'h0C;
                        rs_reg   <= 1'b0;
                        rw_reg   <= 1'b0;
                        TLCD_E   <= 1'b1;
                        state    <= S_INIT_DISP_ON_WAIT;
                    end
                end

                //--------------------------------------------------
                // Display ON 대기
                //--------------------------------------------------
                S_INIT_DISP_ON_WAIT: begin
                    wait_cnt <= wait_cnt + 1'b1;
                    if (wait_cnt == E_PULSE_CYC-1)
                        TLCD_E <= 1'b0;

                    if (wait_cnt >= CMD_WAIT_CYC-1) begin
                        wait_cnt <= 22'd0;
                        state    <= S_IDLE;
                    end
                end

                //--------------------------------------------------
                // IDLE : 초기화 끝, 문자 입력 대기
                //--------------------------------------------------
                S_IDLE: begin
                    ready  <= 1'b1;
                    TLCD_E <= 1'b0;
                    wait_cnt <= 22'd0;

                    if (char_valid) begin
                        // 데이터 쓰기 시작
                        ready    <= 1'b0;
                        data_reg <= char_in;
                        rs_reg   <= 1'b1;   // data
                        rw_reg   <= 1'b0;   // write
                        TLCD_E   <= 1'b1;
                        state    <= S_WRITE_DATA_WAIT;
                    end
                end

                //--------------------------------------------------
                // 데이터 쓰고 대기
                //--------------------------------------------------
                S_WRITE_DATA_WAIT: begin
                    wait_cnt <= wait_cnt + 1'b1;
                    if (wait_cnt == E_PULSE_CYC-1)
                        TLCD_E <= 1'b0;

                    if (wait_cnt >= CMD_WAIT_CYC-1) begin
                        wait_cnt <= 22'd0;
                        state    <= S_IDLE;
                    end
                end

                default: begin
                    state <= S_PWR_WAIT;
                end
            endcase
        end
    end

endmodule
