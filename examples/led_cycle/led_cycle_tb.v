// Simulates `led_cycle`. Checks that exactly one LED is active (low) at all
// times and that, over time, all six are visited. Uses tiny clock parameters so
// a step is only a handful of cycles. Ends in $finish on success; $fatal fails
// the test.
`timescale 1ns / 1ps

module led_cycle_tb;
    localparam integer CLK_HZ = 12;
    localparam integer STEP_HZ = 1;  // DIV = 12 cycles per step

    logic clk = 0;
    logic [5:0] led;

    led_cycle #(
        .CLK_HZ (CLK_HZ),
        .STEP_HZ(STEP_HZ)
    ) dut (
        .clk(clk),
        .led(led)
    );

    always #1 clk = ~clk;

    // Dump a waveform when built by verilog_trace (which compiles with --trace
    // and +define+TRACE). Harmless / excluded under verilog_test.
`ifdef TRACE
    initial begin
        $dumpfile("dump");
        $dumpvars(0, led_cycle_tb);
    end
`endif

    // Number of active (low) LEDs.
    function automatic int active_count(input logic [5:0] v);
        int n = 0;
        for (int i = 0; i < 6; i++) if (v[i] === 1'b0) n++;
        return n;
    endfunction

    int seen = 0;
    initial begin
        for (int c = 0; c < 6 * CLK_HZ * 3; c++) begin
            @(posedge clk);
            if (active_count(led) != 1) begin
                $error("expected exactly one active LED, got led=%b", led);
                $fatal(1);
            end
            for (int i = 0; i < 6; i++) if (led[i] === 1'b0) seen |= (1 << i);
        end

        if (seen[5:0] !== 6'b111111) begin
            $error("not all 6 LEDs were visited; seen=%b", seen[5:0]);
            $fatal(1);
        end

        $display("led_cycle_tb: PASS");
        $finish;
    end
endmodule
