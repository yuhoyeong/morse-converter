// 모스 입력 + 한 글자씩 실시간 LCD 출력 코어
module morse_core (
    input  wire clk,
    input  wire rst_n,

    input  wire btn1,   // dot/dash 입력 버튼
    input  wire btn2,   // 글자 종료 버튼
    input  wire btn3,   // 전체 초기화 버튼

    output wire piezo_out,
    output wire led_long,
    output wire led_short,

    // LCD 쪽으로 내보낼 문자
    output reg  [7:0] lcd_char,
    output reg        lcd_char_valid,   // 1클럭 펄스
    output reg        lcd_done,         // 여기서는 안 씀, 항상 0
    output reg        error_flag_out,   // 에러 플래그

    input  wire       lcd_ready         // LCD 컨트롤러에서 오는 ready
);

    //==========================================================
    // 1. morse_input : dot/dash + 피에조
    //==========================================================
    wire symbol_valid;
    wire symbol_is_dash;

    morse_input u_morse_input (
        .clk          (clk),
        .rst_n        (rst_n),
        .btn1         (btn1),
        .piezo_out    (piezo_out),
        .led_long     (led_long),
        .led_short    (led_short),
        .symbol_valid (symbol_valid),
        .symbol_is_dash(symbol_is_dash)
    );

    //==========================================================
    // 2. 버튼 2, 3 엣지 검출 (디바운스 생략)
    //==========================================================
    reg btn2_d, btn3_d;

    wire btn2_rise = (~btn2_d) & btn2;
    wire btn3_rise = (~btn3_d) & btn3;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            btn2_d <= 1'b0;
            btn3_d <= 1'b0;
        end else begin
            btn2_d <= btn2;
            btn3_d <= btn3;
        end
    end

    //==========================================================
    // 3. 현재 글자 모스 버퍼
    //    - 첫 심볼을 MSB 쪽에 쌓는 방식 (code[5], code[4], ...)
    //==========================================================
    reg [5:0] curr_code;
    reg [2:0] curr_len;

    //==========================================================
    // 4. 문장 저장 메모리 (선택사항, 계속 유지)
    //==========================================================
    reg [7:0] char_mem [0:31];
    reg [5:0] char_index;
    reg       error_flag;

    //==========================================================
    // 5. 모스 → 문자 디코더
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

    integer i;
    reg [7:0] decoded_char;

    //==========================================================
    // 6. 메인 로직
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

        end else begin
            // 기본값
            lcd_char_valid <= 1'b0;
            lcd_done       <= 1'b0;
            error_flag_out <= error_flag;

            //--------------------------------------------------
            // dot/dash 입력 (심볼 하나 확정될 때마다)
            //--------------------------------------------------
            if (symbol_valid) begin
                if (curr_len < 3'd6) begin
                    curr_code[5 - curr_len] <= symbol_is_dash;
                    curr_len                <= curr_len + 1'b1;
                end
            end

            //--------------------------------------------------
            // 글자 종료 버튼(btn2) → 디코드 + 바로 LCD 출력
            //--------------------------------------------------
            if (btn2_rise) begin
                if (curr_len != 3'd0) begin
                    decoded_char = morse_decode(curr_code, curr_len);

                    // 내부 메모리에 저장 (문장 보관용)
                    if (char_index < 6'd32) begin
                        char_mem[char_index] <= decoded_char;
                        char_index           <= char_index + 1'b1;
                    end

                    // 에러 체크
                    if (decoded_char == 8'h3F)
                        error_flag <= 1'b1;

                    // LCD가 준비되었으면 즉시 출력
                    if (lcd_ready) begin
                        lcd_char       <= decoded_char;
                        lcd_char_valid <= 1'b1;  // 1클럭 펄스
                    end

                    // 다음 글자를 위한 버퍼 초기화
                    curr_code <= 6'd0;
                    curr_len  <= 3'd0;
                end
            end

            //--------------------------------------------------
            // btn3: 전체 초기화 (내부 버퍼만 리셋)
            //--------------------------------------------------
            if (btn3_rise) begin
                curr_code   <= 6'd0;
                curr_len    <= 3'd0;
                char_index  <= 6'd0;
                error_flag  <= 1'b0;
                error_flag_out <= 1'b0;

                for (i=0; i<32; i=i+1)
                    char_mem[i] <= 8'd0;

                // 여기서는 LCD에 명령은 따로 안 보냄
                // (lcd_hd44780_ctrl 가 문자 쓰기만 지원하니까)
                // 필요하면 공백 여러 개 찍어서 지우는 방식으로 확장 가능
            end
        end
    end

endmodule
