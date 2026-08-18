`timescale 1ns/1ps

module mac_unpipelined #(
    parameter int DATA_WIDTH = 8
) (
    input logic reset,
    input logic clk,
    input logic [DATA_WIDTH-1:0] a,
    input logic [DATA_WIDTH-1:0] b,
    input logic [DATA_WIDTH-1:0] c,
    input logic [DATA_WIDTH-1:0] d,
    input logic [DATA_WIDTH*2:0] e,
    input logic in_valid,
    input logic out_ready,
    output logic in_ready,
    output logic out_valid,
    output logic [DATA_WIDTH*2+1:0] y
);

    // STAGE 1
    logic [DATA_WIDTH*2+1:0] abcde_s1;
    logic valid_s1;
    logic ready_s1;

    always_ff @(posedge clk) begin
        if (reset) begin
            valid_s1 <= 1'b0;
        end
        else begin
            if (ready_s1) begin
                valid_s1 <= in_valid;

                if (in_valid) begin
                    abcde_s1 <= {2'b00, (DATA_WIDTH*2)'(a) * (DATA_WIDTH*2)'(b)}
                    + {2'b00, (DATA_WIDTH*2)'(c) * (DATA_WIDTH*2)'(d)}
                    + {1'b0, e};
                end
            end
        end
    end

    always_comb begin
        ready_s1 = !valid_s1 || out_ready;

        out_valid = valid_s1;
        in_ready = ready_s1;
        y = abcde_s1;
    end
endmodule