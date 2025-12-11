module rgb_ctrl (
    input  wire error_flag,   // 1 = error, 0 = normal

    output wire led_r,
    output wire led_g,
    output wire led_b
);

    // 공통 캐소드: 1 = ON, 0 = OFF

    assign led_r = (error_flag) ? 1'b1 : 1'b0;  // error → red ON
    assign led_g = (error_flag) ? 1'b0 : 1'b1;  // normal → green ON
    assign led_b = 1'b0;                       // blue OFF

endmodule
