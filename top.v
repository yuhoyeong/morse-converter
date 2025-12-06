module top (
    input  wire clk,
    input  wire rst_n,
    input  wire btn1,
    input  wire btn2,
    input  wire btn3,

    output wire piezo_out,
    output wire led_long,
    output wire led_short,

    // LCD 핀 (보드 핀으로 나감)
    output wire TLCD_D0,
    output wire TLCD_D1,
    output wire TLCD_D2,
    output wire TLCD_D3,
    output wire TLCD_D4,
    output wire TLCD_D5,
    output wire TLCD_D6,
    output wire TLCD_D7,
    output wire TLCD_E,
    output wire TLCD_RS,
    output wire TLCD_RW
);

    wire [7:0] lcd_char;
    wire       lcd_char_valid;
    wire       lcd_done;
    wire       error_flag;
    wire       lcd_ready;      // ★ LCD 준비 신호

    // 1) 모스 입력 + 문자 변환
    morse_core u_morse (
        .clk(clk),
        .rst_n(rst_n),
        .btn1(btn1),
        .btn2(btn2),
        .btn3(btn3),
        .piezo_out(piezo_out),
        .led_long(led_long),
        .led_short(led_short),
        .lcd_char(lcd_char),
        .lcd_char_valid(lcd_char_valid),
        .lcd_done(lcd_done),
        .error_flag_out(error_flag),

        .lcd_ready(lcd_ready)          // ★ 추가
    );

    // 2) LCD 컨트롤러
    lcd_hd44780_ctrl u_lcd (
        .clk(clk),
        .rst_n(rst_n),
        .char_in(lcd_char),
        .char_valid(lcd_char_valid),

        .ready(lcd_ready),             // ★ morse_core로 넘길 준비 신호

        .TLCD_D0(TLCD_D0),
        .TLCD_D1(TLCD_D1),
        .TLCD_D2(TLCD_D2),
        .TLCD_D3(TLCD_D3),
        .TLCD_D4(TLCD_D4),
        .TLCD_D5(TLCD_D5),
        .TLCD_D6(TLCD_D6),
        .TLCD_D7(TLCD_D7),
        .TLCD_RS(TLCD_RS),
        .TLCD_RW(TLCD_RW),
        .TLCD_E (TLCD_E)
    );

endmodule
