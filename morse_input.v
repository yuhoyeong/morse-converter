module morse_input (
    input  wire clk,       // 시스템 클럭 (50MHz 가정)
    input  wire rst_n,     // 리셋 (Active-Low)
    input  wire btn1,      // 1번 버튼 (Active-High 가정)

    output reg  piezo_out, // 피에조 부저 출력 (4kHz 톤)
    output reg  led_long,  // 긴 신호 표시용 LED
    output reg  led_short  // 짧은 신호 표시용 LED
);

    //=========================================================
    // 1. 파라미터
    //    - CNT_MAX : 모스부호 dot/dash 기준 (0.2초)
    //    - TONE_DIV: 50MHz → 4kHz 사각파 분주값
    //         50_000_000 / (2 * 4_000) = 6_250
    //=========================================================
    parameter CLK_FREQ = 32'd50_000_000;
    parameter CNT_MAX  = 32'd10_000_000;  // 0.2초
    parameter TONE_DIV = CLK_FREQ / (32'd2 * 32'd4_000); // 4kHz

    reg [31:0] counter;    // 버튼 누른 시간 카운트
    reg        btn_prev;   // 이전 버튼 상태

    reg [15:0] tone_cnt;   // 피에조 톤 발생용 카운터

    // 버튼 (Active-High)
    wire btn_pressed = btn1;

    //=========================================================
    // 3. 메인 동작 로직
    //=========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter   <= 32'd0;
            btn_prev  <= 1'b0;
            led_long  <= 1'b0;
            led_short <= 1'b0;
            piezo_out <= 1'b0;
            tone_cnt  <= 16'd0;
        end else begin
            // --------------------------------------------------
            // (A) 버튼 누르는 동안: 길이 카운터 + 피에조 톤 발생
            // --------------------------------------------------
            if (btn_pressed) begin
                // 모스부호 길이 카운터
                counter <= counter + 1;

                // 피에조용 4kHz 사각파 생성
                if (tone_cnt >= TONE_DIV - 1) begin
                    tone_cnt  <= 16'd0;
                    piezo_out <= ~piezo_out;  // 출력 토글 → 사각파
                end else begin
                    tone_cnt <= tone_cnt + 1;
                end
            end else begin
                // 버튼 안 누를 때: 카운터는 그대로 두고, 톤 정지
                tone_cnt  <= 16'd0;
                piezo_out <= 1'b0;
            end

            // --------------------------------------------------
            // (B) 버튼에서 손을 떼는 순간(Falling Edge) 길이 판단
            // --------------------------------------------------
            if (btn_prev == 1'b1 && btn_pressed == 1'b0) begin
                if (counter >= CNT_MAX) begin
                    // 긴 모스 신호
                    led_long  <= 1'b1;
                    led_short <= 1'b0;
                end else begin
                    // 짧은 모스 신호
                    led_long  <= 1'b0;
                    led_short <= 1'b1;
                end
                counter <= 32'd0;   // 다음 입력을 위해 리셋
            end

            // 다음 클럭을 위해 버튼 상태 저장
            btn_prev <= btn_pressed;
        end
    end
endmodule
