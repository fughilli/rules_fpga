// A trivial counter that blinks an LED from the board clock. `WIDTH` sets the
// divider so the same source works across boards with very different clocks
// (12 MHz iCEBreaker, 27 MHz Tang Nano 9K) by picking a top bit that toggles at
// a visible rate.
module blinky #(
    parameter WIDTH = 24
) (
    input  wire clk,
    output wire led
);
    reg [WIDTH-1:0] counter = {WIDTH{1'b0}};

    always @(posedge clk) begin
        counter <= counter + 1'b1;
    end

    assign led = counter[WIDTH-1];
endmodule
