// 모스 입력 + 문자 저장 + LCD로 문자열 전송 코어
//  - btn1 : 모스(dot/dash) 입력 (길이)
//  - btn2 : 글자 종료 (현재 모스 패턴 -> 문자로 디코딩해서 메모리에 저장)
//  - btn3 : 전체 메시지 종료, 메모리에 저장된 문자들을 순서대로 lcd_char로 출력
//  - lcd_ready : LCD 컨트롤러가 다음 문자를 받을 준비가 되었는지 확인
module morse_core (
    input  wire clk,
    input  wire rst_n,

    input  wire btn1,  // 모스 입력(길이) 버튼
    input  wire btn2,  // 글자 종료 버튼 (모스 -> 문자)
    input  wire btn3,  // 전체 메시지 종료 버튼

    output wire piezo_out,
    output wire led_long,
    output wire led_short,

    // LCD 쪽으로 내보낼 문자들
    output reg  [7:0] lcd_char,        // 현재 출력 문자 (ASCII)
    output reg        lcd_char_valid,  // 1이면 lcd_char가 유효한 문자 (1클럭 펄스)
    output reg        lcd_done,        // 전체 출력 완료 플래그
    output reg        error_flag_out,  // 디코딩 에러 발생 여부

    // LCD 컨트롤러 상태
    input  wire       lcd_ready        // 1이면 LCD가 새 문자 받을 준비 완료
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
    // 2. 버튼 2, 3 엣지 검출 (디바운스는 생략)
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
    //    - dot=0, dash=1
    //    - 첫 심볼이 code[0], 다음이 code[1] ... 이런 식으로 "아래 비트부터" 저장
    //      → 항상 code[len-1:0]에 유효 패턴이 들어있다고 생각하면 됨.
    //==========================================================
    reg [5:0] curr_code;   // 최대 6비트 모스 패턴
    reg [2:0] curr_len;    // 들어온 심볼 개수 (0~6)

    //==========================================================
    // 4. 문자 저장용 메모리 (최대 32글자)
    //==========================================================
    reg [7:0] char_mem [0:31];
    reg [5:0] char_index;  // 다음에 쓸 인덱스 (0~31)
    reg       error_flag;  // 디코딩 에러 발생 여부

    //==========================================================
    // 5. LCD 출력용 상태머신
    //==========================================================
    localparam S_INPUT = 2'd0;
    localparam S_SEND  = 2'd1; // 어떤 글자를 보낼지 결정 + lcd_ready 기다림
    localparam S_WAIT  = 2'd2; // lcd_char_valid 1클럭 펄스 후, 인덱스 증가
    localparam S_DONE  = 2'd3;

    reg [1:0] state;
    reg [5:0] send_idx;   // LCD로 보내는 현재 인덱스

    //==========================================================
    // 6. 모스 → ASCII 디코딩 함수
    //==========================================================
    function [7:0] morse_decode;
        input [5:0] code;
        input [2:0] len;
        reg   [3:0] p;
        begin
            morse_decode = 8'h3F; // 기본값 '?'

            case (len)
                3'd1: begin
                    // 1심볼 (code[0])
                    if (code[0] == 1'b0)  morse_decode = "E";   // .
                    else                  morse_decode = "T";   // -
                end

                3'd2: begin
                    // 2심볼 (code[1:0])
                    case (code[1:0])
                        2'b00: morse_decode = "I"; // ..
                        2'b01: morse_decode = "A"; // .-
                        2'b10: morse_decode = "N"; // -.
                        2'b11: morse_decode = "M"; // --
                    endcase
                end

                3'd3: begin
                    // 3심볼 (code[2:0])
                    case (code[2:0])
                        3'b000: morse_decode = "S"; // ...
                        3'b001: morse_decode = "U"; // ..-
                        3'b010: morse_decode = "R"; // .-.
                        3'b011: morse_decode = "W"; // .--
                        3'b100: morse_decode = "D"; // -..
                        3'b101: morse_decode = "K"; // -.-
                        3'b110: morse_decode = "G"; // --.
                        3'b111: morse_decode = "O"; // ---
                    endcase
                end

                3'd4: begin
                    // 4심볼 (code[3:0])
                    p = code[3:0];
                    case (p)
                        4'b0000: morse_decode = "H"; // ....
                        4'b0001: morse_decode = "V"; // ...-
                        4'b0010: morse_decode = "F"; // ..-.
                        4'b0100: morse_decode = "L"; // .-..
                        4'b0110: morse_decode = "P"; // .--.
                        4'b0111: morse_decode = "J"; // .---
                        4'b1000: morse_decode = "B"; // -...
                        4'b1001: morse_decode = "X"; // -..-
                        4'b1010: morse_decode = "C"; // -.-.
                        4'b1011: morse_decode = "Y"; // -.--
                        4'b1100: morse_decode = "Z"; // --..
                        4'b1101: morse_decode = "Q"; // --.-
                        default: /* 그대로 '?' */ ;
                    endcase
                end

                default: begin
                    // len 0, 5, 6 등은 여기서 처리 안 함 → '?'
                    morse_decode = 8'h3F;
                end
            endcase
        end
    endfunction

    reg [7:0] decoded_char;
    integer i;

    //==========================================================
    // 7. 메인 로직
    //==========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 초기화
            curr_code   <= 6'd0;
            curr_len    <= 3'd0;
            char_index  <= 6'd0;
            error_flag  <= 1'b0;

            state       <= S_INPUT;
            send_idx    <= 6'd0;
            lcd_char    <= 8'd0;
            lcd_char_valid <= 1'b0;
            lcd_done    <= 1'b0;
            error_flag_out <= 1'b0;

            for (i=0; i<32; i=i+1) begin
                char_mem[i] <= 8'd0;
            end
        end else begin
            // 기본값
            lcd_char_valid <= 1'b0;
            lcd_done       <= 1'b0;

            case (state)
                //------------------------------------------------
                // S_INPUT : 모스 입력 & 문자 저장
                //------------------------------------------------
                S_INPUT: begin
                    // dot/dash 하나 들어올 때마다 LSB부터 채우기
                    if (symbol_valid) begin
                        if (curr_len < 3'd6) begin
                            curr_code[curr_len] <= symbol_is_dash; // code[0]부터 채움
                            curr_len            <= curr_len + 1'b1;
                        end
                    end

                    // 글자 종료 (btn2_rise) → 디코딩 후 char_mem에 저장
                    if (btn2_rise) begin
                        if (curr_len != 3'd0) begin
                            decoded_char = morse_decode(curr_code, curr_len);

                            if (char_index < 6'd32) begin
                                char_mem[char_index] <= decoded_char;
                                char_index           <= char_index + 1'b1;
                            end

                            if (decoded_char == 8'h3F) begin
                                error_flag <= 1'b1;
                            end
                        end

                        // 다음 글자를 위해 패턴 초기화
                        curr_code <= 6'd0;
                        curr_len  <= 3'd0;
                    end

                    // 전체 메시지 종료 (btn3_rise) → SEND 상태로
                    if (btn3_rise) begin
                        send_idx <= 6'd0;
                        state    <= S_SEND;
                    end
                end

                //------------------------------------------------
                // S_SEND : 어떤 글자를 보낼지 결정 + lcd_ready를 기다림
                //------------------------------------------------
                S_SEND: begin
                    error_flag_out <= error_flag;

                    if (error_flag) begin
                        // 에러가 한 번이라도 있었으면 "ERROR"만 출력
                        if (send_idx >= 6'd5) begin
                            lcd_done <= 1'b1;
                            state    <= S_DONE;
                        end else if (lcd_ready) begin
                            // LCD 준비되었을 때 한 글자 전송 시작
                            case (send_idx)
                                6'd0: lcd_char <= "E";
                                6'd1: lcd_char <= "R";
                                6'd2: lcd_char <= "R";
                                6'd3: lcd_char <= "O";
                                6'd4: lcd_char <= "R";
                                default: lcd_char <= " ";
                            endcase
                            lcd_char_valid <= 1'b1;  // 1클럭 펄스
                            state          <= S_WAIT;
                        end
                    end else begin
                        // 정상일 때는 저장된 문자들을 순서대로 출력
                        if (send_idx >= char_index) begin
                            lcd_done <= 1'b1;
                            state    <= S_DONE;
                        end else if (lcd_ready) begin
                            lcd_char       <= char_mem[send_idx];
                            lcd_char_valid <= 1'b1;  // 1클럭 펄스
                            state          <= S_WAIT;
                        end
                    end
                end

                //------------------------------------------------
                // S_WAIT : 방금 보낸 글자에 대해 인덱스를 증가시키는 상태
                //          (lcd_char_valid는 이미 1클럭만 올라갔음)
                //------------------------------------------------
                S_WAIT: begin
                    // 다음 글자로 인덱스 증가
                    send_idx <= send_idx + 1'b1;
                    // 다시 S_SEND로 돌아가서 다음 글자를 준비
                    state    <= S_SEND;
                end

                //------------------------------------------------
                // S_DONE : 출력 완료. btn3 다시 누르면 전체 초기화 후 재시작
                //------------------------------------------------
                S_DONE: begin
                    if (btn3_rise) begin
                        curr_code   <= 6'd0;
                        curr_len    <= 3'd0;
                        char_index  <= 6'd0;
                        error_flag  <= 1'b0;
                        error_flag_out <= 1'b0;

                        for (i=0; i<32; i=i+1) begin
                            char_mem[i] <= 8'd0;
                        end

                        state  <= S_INPUT;
                    end
                end

                default: begin
                    state <= S_INPUT;
                end
            endcase
        end
    end

endmodule
