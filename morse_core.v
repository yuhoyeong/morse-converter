// 모스 입력 + 문자 저장 + LCD 출력 + 모스 재생 (btn4)
module morse_core (
    input  wire clk,
    input  wire rst_n,

    input  wire btn1,   // dot/dash 입력 버튼
    input  wire btn2,   // 글자 종료 버튼
    input  wire btn3,   // 내부 상태 리셋 버튼
    input  wire btn4,   // ★ 지금까지 입력한 문자들을 모스로 재생

    output wire piezo_out,
    output wire led_long,
    output wire led_short,

    // LCD 쪽으로 내보낼 문자
    output reg  [7:0] lcd_char,
    output reg        lcd_char_valid,
    output reg        lcd_done,        // 여기선 사용 X, 항상 0
    output reg        error_flag_out,

    input  wire       lcd_ready
);

    //==========================================================
    // 1. morse_input : dot/dash + LED
    //==========================================================
    wire symbol_valid;
    wire symbol_is_dash;

    morse_input u_morse_input (
        .clk          (clk),
        .rst_n        (rst_n),
        .btn1         (btn1),
        .led_long     (led_long),
        .led_short    (led_short),
        .symbol_valid (symbol_valid),
        .symbol_is_dash(symbol_is_dash)
    );

    //==========================================================
    // 2. 버튼 엣지 검출 (btn2,3,4)
    //==========================================================
    reg btn2_d, btn3_d, btn4_d;

    wire btn2_rise = (~btn2_d) & btn2;
    wire btn3_rise = (~btn3_d) & btn3;
    wire btn4_rise = (~btn4_d) & btn4;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            btn2_d <= 1'b0;
            btn3_d <= 1'b0;
            btn4_d <= 1'b0;
        end else begin
            btn2_d <= btn2;
            btn3_d <= btn3;
            btn4_d <= btn4;
        end
    end

    //==========================================================
    // 3. 현재 글자 모스 버퍼 (첫 심볼이 MSB 쪽)
    //==========================================================
    reg [5:0] curr_code;
    reg [2:0] curr_len;

    //==========================================================
    // 4. 문자 저장 메모리
    //==========================================================
    reg [7:0] char_mem [0:31];
    reg [5:0] char_index;
    reg       error_flag;

    //==========================================================
    // 5. 모스 → 문자 디코더 (입력용)
    //==========================================================
    function [7:0] morse_decode;
        input [5:0] code;
        input [2:0] len;
        begin
            morse_decode = 8'h3F; // '?'

            case(len)
                3'd1: begin
                    case(code[5])
                        1'b0: morse_decode = "E";
                        1'b1: morse_decode = "T";
                    endcase
                end
                3'd2: begin
                    case(code[5:4])
                        2'b00: morse_decode = "I";
                        2'b01: morse_decode = "A";
                        2'b10: morse_decode = "N";
                        2'b11: morse_decode = "M";
                    endcase
                end
                3'd3: begin
                    case(code[5:3])
                        3'b000: morse_decode = "S";
                        3'b001: morse_decode = "U";
                        3'b010: morse_decode = "R";
                        3'b011: morse_decode = "W";
                        3'b100: morse_decode = "D";
                        3'b101: morse_decode = "K";
                        3'b110: morse_decode = "G";
                        3'b111: morse_decode = "O";
                    endcase
                end
                3'd4: begin
                    case(code[5:2])
                        4'b0000: morse_decode = "H";
                        4'b0001: morse_decode = "V";
                        4'b0010: morse_decode = "F";
                        4'b0100: morse_decode = "L";
                        4'b0110: morse_decode = "P";
                        4'b0111: morse_decode = "J";
                        4'b1000: morse_decode = "B";
                        4'b1001: morse_decode = "X";
                        4'b1010: morse_decode = "C";
                        4'b1011: morse_decode = "Y";
                        4'b1100: morse_decode = "Z";
                        4'b1101: morse_decode = "Q";
                    endcase
                end
            endcase
        end
    endfunction

    //==========================================================
    // 6. 문자 → 모스 인코더 (재생용)
    //     pattern[5] 가 첫 심볼, len은 심볼 개수
    //==========================================================
    function [5:0] morse_pattern;
        input [7:0] ch;
        begin
            case (ch)
                "E": morse_pattern = 6'b000000; // .
                "T": morse_pattern = 6'b100000; // -

                "I": morse_pattern = 6'b000000; // ..
                "A": morse_pattern = 6'b010000; // .-
                "N": morse_pattern = 6'b100000; // -.
                "M": morse_pattern = 6'b110000; // --

                "S": morse_pattern = 6'b000000; // ...
                "U": morse_pattern = 6'b001000; // ..-
                "R": morse_pattern = 6'b010000; // .-.
                "W": morse_pattern = 6'b011000; // .--
                "D": morse_pattern = 6'b100000; // -..
                "K": morse_pattern = 6'b101000; // -.-
                "G": morse_pattern = 6'b110000; // --.
                "O": morse_pattern = 6'b111000; // ---

                "H": morse_pattern = 6'b000000; // ....
                "V": morse_pattern = 6'b000100; // ...-
                "F": morse_pattern = 6'b001000; // ..-.
                "L": morse_pattern = 6'b010000; // .-..
                "P": morse_pattern = 6'b011000; // .--.
                "J": morse_pattern = 6'b011100; // .---
                "B": morse_pattern = 6'b100000; // -...
                "X": morse_pattern = 6'b100100; // -..-
                "C": morse_pattern = 6'b101000; // -.-.
                "Y": morse_pattern = 6'b101100; // -.--
                "Z": morse_pattern = 6'b110000; // --..
                "Q": morse_pattern = 6'b110100; // --.-
                default: morse_pattern = 6'b000000;
            endcase
        end
    endfunction

    function [2:0] morse_length;
        input [7:0] ch;
        begin
            case (ch)
                "E","T": morse_length = 3'd1;

                "I","A","N","M": morse_length = 3'd2;

                "S","U","R","W","D","K","G","O": morse_length = 3'd3;

                // 4심볼
                "H","V","F","L","P","J","B","X","C","Y","Z","Q": morse_length = 3'd4;

                default: morse_length = 3'd0;
            endcase
        end
    endfunction

    //==========================================================
    // 7. 피에조 4kHz 톤 발생 (beep_enable이 1일 때만 울림)
    //==========================================================
    parameter integer CLK_FREQ  = 50_000_000;
    parameter integer TONE_DIV  = CLK_FREQ / (2 * 400);

    reg [15:0] tone_cnt;
    reg        piezo_ff;
    reg        beep_enable;   // 1이면 소리 ON

    assign piezo_out = beep_enable ? piezo_ff : 1'b0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tone_cnt <= 16'd0;
            piezo_ff <= 1'b0;
        end else begin
            if (beep_enable) begin
                if (tone_cnt >= TONE_DIV-1) begin
                    tone_cnt <= 16'd0;
                    piezo_ff <= ~piezo_ff;
                end else begin
                    tone_cnt <= tone_cnt + 1'b1;
                end
            end else begin
                tone_cnt <= 16'd0;
                piezo_ff <= 1'b0;
            end
        end
    end

    //==========================================================
    // 8. 재생용 상태/타이머
    //==========================================================
    localparam S_INPUT     = 1'b0;
    localparam S_PLAYBACK  = 1'b1;

    reg        state;

    reg [5:0]  play_char_idx;    // char_mem 인덱스
    reg [2:0]  play_sym_idx;     // 문자 내 심볼 인덱스 (0~5)
    reg [5:0]  play_pattern;
    reg [2:0]  play_len;

    reg [31:0] time_cnt;
    reg [1:0]  pb_state;

    localparam PB_IDLE       = 2'd0;
    localparam PB_BEEP       = 2'd1;
    localparam PB_GAP        = 2'd2;
    localparam PB_LETTER_GAP = 2'd3;

    // 타이밍 (입력 기준과 비슷하게)
    localparam integer DOT_TICKS        = CLK_FREQ / 5;     // 0.2s
    localparam integer DASH_TICKS       = DOT_TICKS * 3;    // 0.6s
    localparam integer GAP_TICKS        = DOT_TICKS;        // 심볼 간 0.2s
    localparam integer LETTER_GAP_TICKS = DOT_TICKS * 3;    // 글자 간 0.6s

    integer i;
    reg [7:0] decoded_char;

    //==========================================================
    // 9. 메인 로직
    //==========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            curr_code   <= 6'd0;
            curr_len    <= 3'd0;
            char_index  <= 6'd0;
            error_flag  <= 1'b0;

            lcd_char       <= 8'd0;
            lcd_char_valid <= 1'b0;
            lcd_done       <= 1'b0;
            error_flag_out <= 1'b0;

            for (i=0; i<32; i=i+1)
                char_mem[i] <= 8'd0;

            state        <= S_INPUT;
            play_char_idx<= 6'd0;
            play_sym_idx <= 3'd0;
            play_pattern <= 6'd0;
            play_len     <= 3'd0;
            time_cnt     <= 32'd0;
            pb_state     <= PB_IDLE;
            beep_enable  <= 1'b0;
        end else begin
            // 기본값
            lcd_char_valid <= 1'b0;
            lcd_done       <= 1'b0;
            error_flag_out <= error_flag;

            case (state)
                //------------------------------------------------
                // 입력 모드
                //------------------------------------------------
                S_INPUT: begin
                    // 입력 중에는 btn1을 누르는 동안 피에조 울리게 할 수도 있음
                    // (원하면: beep_enable <= btn1;)
                    beep_enable <= btn1;

                    // dot/dash 심볼 저장
                    if (symbol_valid) begin
                        if (curr_len < 3'd6) begin
                            curr_code[5 - curr_len] <= symbol_is_dash;
                            curr_len                <= curr_len + 1'b1;
                        end
                    end

                    // 글자 종료 (btn2)
                    if (btn2_rise) begin
                        if (curr_len != 3'd0) begin
                            decoded_char = morse_decode(curr_code, curr_len);

                            // 메모리에 저장
                            if (char_index < 6'd32) begin
                                char_mem[char_index] <= decoded_char;
                                char_index           <= char_index + 1'b1;
                            end

                            // 에러 체크
                            if (decoded_char == 8'h3F)
                                error_flag <= 1'b1;

                            // LCD에 즉시 출력
                            if (lcd_ready) begin
                                lcd_char       <= decoded_char;
                                lcd_char_valid <= 1'b1;
                            end

                            // 다음 글자를 위해 초기화
                            curr_code <= 6'd0;
                            curr_len  <= 3'd0;
                        end
                    end

                    // 내부 상태 리셋 (btn3)
                    if (btn3_rise) begin
                        curr_code   <= 6'd0;
                        curr_len    <= 3'd0;
                        char_index  <= 6'd0;
                        error_flag  <= 1'b0;
                        error_flag_out <= 1'b0;

                        for (i=0; i<32; i=i+1)
                            char_mem[i] <= 8'd0;
                    end

                    // 재생 시작 (btn4)
                    if (btn4_rise && char_index != 0) begin
                        state         <= S_PLAYBACK;
                        play_char_idx <= 6'd0;
                        play_sym_idx  <= 3'd0;
                        play_pattern  <= morse_pattern(char_mem[0]);
                        play_len      <= morse_length(char_mem[0]);
                        time_cnt      <= 32'd0;
                        pb_state      <= (play_len == 0) ? PB_LETTER_GAP : PB_BEEP;
                        beep_enable   <= 1'b0;   // 재생 FSM에서만 제어
                    end
                end

                //------------------------------------------------
                // 재생 모드
                //------------------------------------------------
                S_PLAYBACK: begin
                    case (pb_state)
                        PB_BEEP: begin
                            if (play_sym_idx >= play_len) begin
                                // 모든 심볼 다 했으면 글자 간 공백으로
                                beep_enable <= 1'b0;
                                time_cnt    <= 32'd0;
                                pb_state    <= PB_LETTER_GAP;
                            end else begin
                                // 현재 심볼 (MSB부터)
                                // 0: dot, 1: dash
                                if (play_pattern[5 - play_sym_idx] == 1'b0) begin
                                    // dot
                                    beep_enable <= 1'b1;
                                    if (time_cnt >= DOT_TICKS-1) begin
                                        time_cnt    <= 32'd0;
                                        beep_enable <= 1'b0;
                                        pb_state    <= PB_GAP;
                                    end else begin
                                        time_cnt <= time_cnt + 1'b1;
                                    end
                                end else begin
                                    // dash
                                    beep_enable <= 1'b1;
                                    if (time_cnt >= DASH_TICKS-1) begin
                                        time_cnt    <= 32'd0;
                                        beep_enable <= 1'b0;
                                        pb_state    <= PB_GAP;
                                    end else begin
                                        time_cnt <= time_cnt + 1'b1;
                                    end
                                end
                            end
                        end

                        PB_GAP: begin
                            // 심볼 간 공백
                            beep_enable <= 1'b0;
                            if (time_cnt >= GAP_TICKS-1) begin
                                time_cnt    <= 32'd0;
                                play_sym_idx<= play_sym_idx + 1'b1;
                                pb_state    <= PB_BEEP;
                            end else begin
                                time_cnt <= time_cnt + 1'b1;
                            end
                        end

                        PB_LETTER_GAP: begin
                            // 글자 간 공백
                            beep_enable <= 1'b0;
                            if (time_cnt >= LETTER_GAP_TICKS-1) begin
                                time_cnt      <= 32'd0;
                                play_char_idx <= play_char_idx + 1'b1;
                                play_sym_idx  <= 3'd0;

                                if (play_char_idx >= char_index) begin
                                    // 전체 재생 종료
                                    state       <= S_INPUT;
                                    pb_state    <= PB_IDLE;
                                    beep_enable <= 1'b0;
                                end else begin
                                    play_pattern <= morse_pattern(char_mem[play_char_idx]);
                                    play_len     <= morse_length(char_mem[play_char_idx]);
                                    pb_state     <= (play_len == 0) ? PB_LETTER_GAP : PB_BEEP;
                                end
                            end else begin
                                time_cnt <= time_cnt + 1'b1;
                            end
                        end

                        default: begin
                            pb_state    <= PB_IDLE;
                            state       <= S_INPUT;
                            beep_enable <= 1'b0;
                        end
                    endcase
                end
            endcase
        end
    end

endmodule
