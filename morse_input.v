// 1번 버튼으로 모스부호(길이) 입력 + dot/dash 판단
module morse_input (
    input  wire clk,        // 시스템 클럭 (50MHz 가정)
    input  wire rst_n,      // 리셋 (Active-Low)
    input  wire btn1,       // 1번 버튼 (Active-High)

    output reg  led_long,   // 긴 신호 표시용 LED
    output reg  led_short,  // 짧은 신호 표시용 LED

    // 상위로 전달할 모스 심볼 정보
    output reg  symbol_valid,    // 이 클럭에 dot/dash 하나 확정되었음
    output reg  symbol_is_dash   // 1: dash(긴 신호), 0: dot(짧은 신호)
);

    //=========================================================
    // 파라미터
    //=========================================================
    parameter CLK_FREQ = 32'd50_000_000;
    parameter CNT_MAX  = 32'd10_000_000;                // 0.2초 기준

    reg [31:0] counter;   // 버튼 누른 시간 카운트
    reg        btn_prev;  // 이전 버튼 상태

    wire btn_pressed = btn1;

    //=========================================================
    // 메인 동작
    //=========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter        <= 32'd0;
            btn_prev       <= 1'b0;
            led_long       <= 1'b0;
            led_short      <= 1'b0;
            symbol_valid   <= 1'b0;
            symbol_is_dash <= 1'b0;
        end else begin
            symbol_valid <= 1'b0;  // 기본값

            // (A) 버튼 누르는 동안: 카운터 증가
            if (btn_pressed) begin
                counter <= counter + 1;
            end

            // (B) Falling Edge에서 길이 판단
            if (btn_prev == 1'b1 && btn_pressed == 1'b0) begin
                if (counter >= CNT_MAX) begin
                    // 긴 모스 신호 (dash)
                    led_long       <= 1'b1;
                    led_short      <= 1'b0;
                    symbol_is_dash <= 1'b1;
                end else begin
                    // 짧은 모스 신호 (dot)
                    led_long       <= 1'b0;
                    led_short      <= 1'b1;
                    symbol_is_dash <= 1'b0;
                end

                symbol_valid <= 1'b1;   // 이번 클럭에 dot/dash 하나 확정
                counter      <= 32'd0;  // 다음 입력을 위해 리셋
            end

            btn_prev <= btn_pressed;
        end
    end

endmodule
