`timescale 1ns/1ps

module mac_pipe2_tb;

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

    logic random_phase_done;

    //------------------------------------------------------------
    // DUT
    //------------------------------------------------------------

    mac_pipe2 #(
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
    // Stall-stability monitor
    //------------------------------------------------------------

    logic stalled_last_cycle;
    logic [Y_WIDTH-1:0] stalled_y;

    always @(posedge clk) begin
        if (reset) begin
            stalled_last_cycle <= 1'b0;
            stalled_y          <= '0;
        end else begin

            // If the output was stalled and remains stalled,
            // the transaction must still be present and unchanged.
            if (stalled_last_cycle && !out_ready) begin
                assert (out_valid)
                    else $fatal(
                        1,
                        "out_valid deasserted while output remained stalled"
                    );

                assert (y === stalled_y)
                    else $fatal(
                        1,
                        "Output payload changed while stalled"
                    );
            end

            if (out_valid && !out_ready) begin
                stalled_last_cycle <= 1'b1;
                stalled_y          <= y;
            end else begin
                stalled_last_cycle <= 1'b0;
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
    // Waveform
    //------------------------------------------------------------

    initial begin
        $dumpfile("results/waveform.vcd");
        $dumpvars(1, mac_pipe2_tb);
    end

    //------------------------------------------------------------
    // Test sequence
    //------------------------------------------------------------

    initial begin

        reset             = 1'b1;
        in_valid          = 1'b0;
        out_ready         = 1'b1;
        random_phase_done = 1'b0;

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

        @(posedge clk);

        assert (!out_valid)
            else $fatal(1, "out_valid asserted after reset");

        assert (in_ready)
            else $fatal(1, "DUT not ready after reset");

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
        // Test 5: Consumer stall and backpressure
        //--------------------------------------------------------

        @(negedge clk);
        out_ready = 1'b0;

        fork

            // Keep presenting traffic. This process will naturally
            // block once backpressure reaches the input.
            begin : stalled_producer
                for (int i = 0; i < 8; i++) begin
                    send_transaction(
                        8'($urandom),
                        8'($urandom),
                        8'($urandom),
                        8'($urandom),
                        17'($urandom)
                    );
                end
            end

            // Explicitly prove that the blocked consumer eventually
            // propagates backpressure to the producer.
            begin : backpressure_check
                int timeout;

                timeout = 0;

                while (in_ready && timeout < 12) begin
                    @(posedge clk);
                    timeout++;
                end

                assert (!in_ready)
                    else $fatal(
                        1,
                        "Backpressure did not propagate to input"
                    );
            end

            // Keep the consumer stalled long enough for the finite
            // pipeline to fill, then allow it to drain again.
            begin : stall_release
                repeat (12) @(posedge clk);

                @(negedge clk);
                out_ready = 1'b1;
            end

        join

        //--------------------------------------------------------
        // Test 6: Mid-traffic reset
        //--------------------------------------------------------

        // Force a valid transaction to remain buffered.
        @(negedge clk);
        out_ready = 1'b0;

        send_transaction(
            8'd13,
            8'd7,
            8'd5,
            8'd9,
            17'd11
        );

        // Reset while the transaction is still pending.
        @(negedge clk);
        reset = 1'b1;

        repeat (2) @(posedge clk);

        @(negedge clk);
        reset     = 1'b0;
        out_ready = 1'b1;

        @(posedge clk);

        assert (!out_valid)
            else $fatal(
                1,
                "Pipeline retained valid output across reset"
            );

        assert (in_ready)
            else $fatal(
                1,
                "DUT did not recover readiness after reset"
            );

        assert (expected_queue.size() == 0)
            else $fatal(
                1,
                "Scoreboard was not cleared by reset"
            );

        //--------------------------------------------------------
        // Test 7: Randomized traffic with randomized stalls
        //--------------------------------------------------------

        random_phase_done = 1'b0;

        fork

            begin : random_producer
                for (int i = 0; i < 40; i++) begin
                    send_transaction(
                        8'($urandom),
                        8'($urandom),
                        8'($urandom),
                        8'($urandom),
                        17'($urandom)
                    );
                end

                random_phase_done = 1'b1;
            end

            begin : random_consumer
                int consecutive_stalls;

                consecutive_stalls = 0;

                while (!random_phase_done) begin
                    @(negedge clk);

                    // Bound consecutive random stalls so the regression
                    // always continues making progress.
                    if (consecutive_stalls >= 3) begin
                        out_ready         = 1'b1;
                        consecutive_stalls = 0;
                    end else begin
                        out_ready = 1'($urandom_range(0, 1));

                        if (!out_ready)
                            consecutive_stalls++;
                        else
                            consecutive_stalls = 0;
                    end
                end

                @(negedge clk);
                out_ready = 1'b1;
            end

        join

        //--------------------------------------------------------
        // Drain pipeline
        //--------------------------------------------------------

        in_valid  = 1'b0;
        out_ready = 1'b1;

        while (expected_queue.size() != 0)
            @(posedge clk);

        repeat (3) @(posedge clk);

        assert (!out_valid)
            else $fatal(
                1,
                "out_valid remained asserted after pipeline drained"
            );

        $display("PASS: mac_pipe2 verification complete");

        $finish;
    end

endmodule