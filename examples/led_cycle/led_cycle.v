// Walk a single lit LED across the Tang Nano 9K's 6 onboard LEDs.
//
// The onboard LEDs are active-low, so a lit LED is driven to 0. `idx` selects
// which LED is on and advances STEP_HZ times per second, derived from the board
// clock by a prescaler. Parameters make the rate overridable from a testbench.
module led_cycle #(
    parameter integer CLK_HZ = 27_000_000,
    parameter integer STEP_HZ = 5
) (
    input  wire       clk,
    output wire [5:0] led
);
    localparam integer DIV = CLK_HZ / STEP_HZ;
    localparam integer CW = $clog2(DIV);

    reg [CW-1:0] tick = 0;
    reg [2:0]    idx = 0;

    always @(posedge clk) begin
        if (tick == DIV[CW-1:0] - 1'b1) begin
            tick <= 0;
            idx  <= (idx == 3'd5) ? 3'd0 : idx + 3'd1;
        end else begin
            tick <= tick + 1'b1;
        end
    end

    // One-hot select, inverted for the active-low LEDs.
    assign led = ~(6'b000001 << idx);
endmodule
