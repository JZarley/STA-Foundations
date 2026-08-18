`timescale 1ns/1ps

module mac_pipe1_tb;

    localparam int DATA_WIDTH = 8;
    localparam int E_WIDTH    = 2*DATA_WIDTH + 1;
    localparam int Y_WIDTH    = 2*DATA_WIDTH + 2;

    logic clk;
    logic reset;

    logic in_valid;
    logic in_ready;

    logic [DATA_WIDTH-1:0] a;
    logic [DATA_WIDTH-1:0] b;
    logic [DATA_WIDTH-1:0] c;
    logic [DATA_WIDTH-1:0] d;
    logic [E_WIDTH-1:0]    e;

    logic out_valid;
    logic out_ready;
    logic [Y_WIDTH-1:0] y;

    //------------------------------------------------------------
    // DUT
    //------------------------------------------------------------

    mac_pipe1 #(
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk       (clk),
        .reset     (reset),

        .in_valid  (in_valid),
        .in_ready  (in_ready),

        .a         (a),
        .b         (b),
        .c         (c),
        .d         (d),
        .e         (e),

        .out_valid (out_valid),
        .out_ready (out_ready),
        .y         (y)
    );

    //------------------------------------------------------------
    // Clock
    //------------------------------------------------------------

    initial clk = 1'b0;
    always #5 clk = ~clk;

    //------------------------------------------------------------
    // Reference-model queue
    //------------------------------------------------------------

    logic [Y_WIDTH-1:0] expected_queue[$];

    function automatic logic [Y_WIDTH-1:0] expected_mac(
        input logic [DATA_WIDTH-1:0] a_f,
        input logic [DATA_WIDTH-1:0] b_f,
        input logic [DATA_WIDTH-1:0] c_f,
        input logic [DATA_WIDTH-1:0] d_f,
        input logic [E_WIDTH-1:0]    e_f
    );

        logic [2*DATA_WIDTH-1:0] ab;
        logic [2*DATA_WIDTH-1:0] cd;
        logic [2*DATA_WIDTH:0]   abcd;

        begin
            ab   = a_f * b_f;
            cd   = c_f * d_f;
            abcd = {1'b0, ab} + {1'b0, cd};

            expected_mac =
                {1'b0, abcd}
                +
                {1'b0, e_f};
        end

    endfunction

    //------------------------------------------------------------
    // Scoreboard
    //------------------------------------------------------------

    always @(posedge clk) begin
        logic [Y_WIDTH-1:0] expected;

        if (reset) begin
            expected_queue.delete();
        end else begin

            // Transaction accepted by DUT
            if (in_valid && in_ready) begin
                expected_queue.push_back(
                    expected_mac(a, b, c, d, e)
                );
            end

            // Transaction consumed by downstream
            if (out_valid && out_ready) begin

                assert (expected_queue.size() > 0)
                    else $fatal(
                        1,
                        "DUT produced an output when scoreboard was empty"
                    );

                expected = expected_queue.pop_front();

                assert (y === expected)
                    else $fatal(
                        1,
                        "MAC mismatch: expected=%0h actual=%0h",
                        expected,
                        y
                    );

            end
        end
    end

    //------------------------------------------------------------
    // Helper task
    //------------------------------------------------------------

    task automatic send_transaction(
        input logic [DATA_WIDTH-1:0] a_t,
        input logic [DATA_WIDTH-1:0] b_t,
        input logic [DATA_WIDTH-1:0] c_t,
        input logic [DATA_WIDTH-1:0] d_t,
        input logic [E_WIDTH-1:0]    e_t
    );

        begin
            @(negedge clk);

            a        = a_t;
            b        = b_t;
            c        = c_t;
            d        = d_t;
            e        = e_t;
            in_valid = 1'b1;

            // Hold transaction until DUT accepts it.
            do begin
                @(posedge clk);
            end while (!in_ready);

            @(negedge clk);
            in_valid = 1'b0;
        end

    endtask

    //------------------------------------------------------------
    // Test sequence
    //------------------------------------------------------------
    initial begin
        $dumpfile("waveform.vcd");
        $dumpvars(1, mac_pipe1_tb);
    end
    initial begin

        reset     = 1'b1;

        in_valid  = 1'b0;
        out_ready = 1'b1;

        a = '0;
        b = '0;
        c = '0;
        d = '0;
        e = '0;

        //--------------------------------------------------------
        // Reset
        //--------------------------------------------------------

        repeat (3) @(posedge clk);

        @(negedge clk);
        reset = 1'b0;

        //--------------------------------------------------------
        // Test 1: Basic arithmetic
        //--------------------------------------------------------

        send_transaction(
            8'd2,
            8'd3,
            8'd4,
            8'd5,
            17'd10
        );

        // Expected:
        // (2*3) + (4*5) + 10 = 36

        //--------------------------------------------------------
        // Test 2: Back-to-back transactions
        //--------------------------------------------------------

        @(negedge clk);

        a        = 8'd3;
        b        = 8'd7;
        c        = 8'd2;
        d        = 8'd9;
        e        = 17'd5;
        in_valid = 1'b1;

        @(posedge clk);

        @(negedge clk);

        a = 8'd10;
        b = 8'd11;
        c = 8'd4;
        d = 8'd6;
        e = 17'd20;

        @(posedge clk);

        @(negedge clk);

        a = 8'd12;
        b = 8'd13;
        c = 8'd2;
        d = 8'd3;
        e = 17'd7;

        @(posedge clk);

        @(negedge clk);
        in_valid = 1'b0;

        //--------------------------------------------------------
        // Test 3: Bubble propagation
        //--------------------------------------------------------

        repeat (2) @(posedge clk);

        send_transaction(
            8'd5,
            8'd5,
            8'd6,
            8'd6,
            17'd4
        );

        //--------------------------------------------------------
        // Test 4: Maximum values / width checking
        //--------------------------------------------------------

        send_transaction(
            {DATA_WIDTH{1'b1}},
            {DATA_WIDTH{1'b1}},
            {DATA_WIDTH{1'b1}},
            {DATA_WIDTH{1'b1}},
            {E_WIDTH{1'b1}}
        );

        //--------------------------------------------------------
        // Test 5: Consumer stall
        //--------------------------------------------------------

        send_transaction(
            8'd20,
            8'd4,
            8'd3,
            8'd7,
            17'd9
        );

        send_transaction(
            8'd8,
            8'd8,
            8'd9,
            8'd9,
            17'd1
        );

        // Stall downstream long enough for pressure to propagate.
        @(negedge clk);
        out_ready = 1'b0;

        repeat (5) @(posedge clk);

        @(negedge clk);
        out_ready = 1'b1;

        //--------------------------------------------------------
        // Test 6: Sustained traffic
        //--------------------------------------------------------

        for (int i = 0; i < 20; i++) begin
            send_transaction(
                8'($urandom),
                8'($urandom),
                8'($urandom),
                8'($urandom),
                17'($urandom)
            );
        end

        //--------------------------------------------------------
        // Drain pipeline
        //--------------------------------------------------------

        in_valid  = 1'b0;
        out_ready = 1'b1;

        while (expected_queue.size() != 0)
            @(posedge clk);

        repeat (3) @(posedge clk);

        assert (!out_valid)
            else $fatal(1, "out_valid remained asserted after pipeline drained");

        $display("PASS: mac_pipe1 verification complete");

        $finish;
    end

endmodule