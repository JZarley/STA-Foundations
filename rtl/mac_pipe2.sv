`timescale 1ns/1ps

module mac_pipe2 #(
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
    logic [DATA_WIDTH*2-1:0] ab_s1;
    logic [DATA_WIDTH*2-1:0] cd_s1;
    logic [DATA_WIDTH*2:0] e_s1;
    logic valid_s1;
    logic ready_s1;

    // STAGE 2
    logic [DATA_WIDTH*2:0] abcd_s2;
    logic [DATA_WIDTH*2:0] e_s2;
    logic valid_s2;
    logic ready_s2;

    // STAGE 3
    logic [DATA_WIDTH*2+1:0] abcde_s3;
    logic valid_s3;
    logic ready_s3;

    always_ff @(posedge clk) begin
        if (reset) begin
            valid_s1 <= 1'b0;
            valid_s2 <= 1'b0;
            valid_s3 <= 1'b0;
        end
        else begin
            if (ready_s3) begin
                valid_s3 <= valid_s2;

                if (valid_s2) begin    
                    abcde_s3 <= {1'b0, abcd_s2} + {1'b0, e_s2};
                end
            end

            if (ready_s2) begin
                valid_s2 <= valid_s1;

                if (valid_s1) begin
                    abcd_s2 <= {1'b0, ab_s1} + {1'b0, cd_s1};
                    e_s2 <= e_s1;
                end
            end

            if (ready_s1) begin
                valid_s1 <= in_valid;

                if (in_valid) begin
                    ab_s1 <= (DATA_WIDTH*2)'(a) * (DATA_WIDTH*2)'(b);
                    cd_s1 <= (DATA_WIDTH*2)'(c) * (DATA_WIDTH*2)'(d);
                    e_s1 <= e;
                end
            end
        end
    end

    always_comb begin
        ready_s3 = !valid_s3 || out_ready;
        ready_s2 = !valid_s2 || ready_s3;
        ready_s1 = !valid_s1 || ready_s2;

        out_valid = valid_s3;
        in_ready = ready_s1;
        y = abcde_s3;
    end
endmodule