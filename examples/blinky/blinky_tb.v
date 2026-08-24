// Verilator testbench for `blinky`. Drives the clock and checks that the LED
// output is a valid level and actually toggles over the counter period. Ends in
// $finish on success; $fatal (non-zero exit) fails the Bazel test.
`timescale 1ns / 1ps

module blinky_tb;
    localparam WIDTH = 4;

    logic clk = 0;
    logic led;

    blinky #(.WIDTH(WIDTH)) dut (
        .clk(clk),
        .led(led)
    );

    // 2ns period clock (needs verilator --timing, which verilog_test passes).
    always #1 clk = ~clk;

    initial begin
        logic seen_high = 0;
        logic seen_low = 0;

        // Run through more than one full counter period (2^WIDTH toggles of the
        // top bit take 2^WIDTH cycles).
        for (int i = 0; i < (1 << (WIDTH + 1)); i++) begin
            @(posedge clk);
            if (led !== 1'b0 && led !== 1'b1) begin
                $error("led is not a valid logic level: %b", led);
                $fatal(1);
            end
            if (led === 1'b1) seen_high = 1;
            if (led === 1'b0) seen_low = 1;
        end

        if (!(seen_high && seen_low)) begin
            $error("led did not toggle (high=%b low=%b)", seen_high, seen_low);
            $fatal(1);
        end

        $display("blinky_tb: PASS");
        $finish;
    end
endmodule
