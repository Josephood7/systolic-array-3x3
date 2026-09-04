module systolic_top #(
    parameter int DATA_WIDTH = 4,
    parameter int PSUM_WIDTH = 9,
    parameter int NUM_PE     = 3,
    parameter int ROW_WIDTH  = (NUM_PE <= 1) ? 1 : $clog2(NUM_PE)
)(
    input  logic clk,
    input  logic rst_n,

    input  logic in_valid,
    output logic in_ready,
    input  logic signed [DATA_WIDTH-1:0] a_in [NUM_PE-1:0][NUM_PE-1:0],
    input  logic signed [DATA_WIDTH-1:0] b_in [NUM_PE-1:0][NUM_PE-1:0],

    output logic out_valid,
    output logic signed [PSUM_WIDTH-1:0] c_out [NUM_PE-1:0][NUM_PE-1:0]
);

    localparam int COUNT_WIDTH = (NUM_PE <= 1) ? 1 : $clog2(NUM_PE);
    localparam int A_PIPE_DEPTH = 3*NUM_PE-1;
    localparam int W_PIPE_DEPTH = 2*NUM_PE-1;
    localparam int DONE_DEPTH   = 4*NUM_PE-1;
    localparam int DONE_DELAY   = 4*NUM_PE-3;

    // The active_bank is the write pointer, read_bank flips for every launched
    // Local buffers are double-buffered to allow a new matrix to be queued while the previous one is still running.  
    // The buffers are indexed by [bank][row][col].
    logic active_bank;
    logic read_bank;
    logic [1:0] buffer_valid;
    logic signed [DATA_WIDTH-1:0] a_buffer [1:0][NUM_PE-1:0][NUM_PE-1:0];
    logic signed [DATA_WIDTH-1:0] b_buffer [1:0][NUM_PE-1:0][NUM_PE-1:0];
    logic signed [PSUM_WIDTH-1:0] c_buffer [1:0][NUM_PE-1:0][NUM_PE-1:0];

    // The counter is zero when a matrix may launch.
    logic [COUNT_WIDTH-1:0] matrix_counter;
    logic queued_launch, direct_launch, launch_event, launch_bank, accept_event, buffer_write;

    // Parallel-loaded activation delay lines.  
    // Matrix row r for physical PE (fixed constant)
    // lane k is scheduled NUM_PE+r+k clocks after the weight-wave launch.
    logic signed [DATA_WIDTH-1:0] a_data_pipe  [NUM_PE-1:0][A_PIPE_DEPTH-1:0];
    logic                         a_valid_pipe [NUM_PE-1:0][A_PIPE_DEPTH-1:0];
    logic                         a_bank_pipe  [NUM_PE-1:0][A_PIPE_DEPTH-1:0];
    logic        [ROW_WIDTH-1:0]  a_row_pipe   [NUM_PE-1:0][A_PIPE_DEPTH-1:0];

    // Weight delay lines form the bottom-row-first, column-skewed preload wave.
    logic signed [DATA_WIDTH-1:0] wgt_data_pipe [NUM_PE-1:0][W_PIPE_DEPTH-1:0];
    logic                         wgt_load_pipe [NUM_PE-1:0][W_PIPE_DEPTH-1:0];
    logic                         wgt_bank_pipe [NUM_PE-1:0][W_PIPE_DEPTH-1:0];

    logic done_valid_pipe [DONE_DEPTH-1:0];
    logic done_bank_pipe  [DONE_DEPTH-1:0];

    // systolic array input and output ports
    logic signed [DATA_WIDTH-1:0] arr_a_in [NUM_PE-1:0];
    logic signed [DATA_WIDTH-1:0] arr_b_in [NUM_PE-1:0];
    logic        [NUM_PE-1:0]     arr_a_valid;
    logic        [NUM_PE-1:0]     arr_a_bank;
    logic        [ROW_WIDTH-1:0]  arr_a_row [NUM_PE-1:0];

    logic        [NUM_PE-1:0]     arr_c_valid;
    logic        [NUM_PE-1:0]     arr_c_bank;
    logic        [ROW_WIDTH-1:0]  arr_c_row [NUM_PE-1:0];
    logic signed [PSUM_WIDTH-1:0] arr_c_out [NUM_PE-1:0];

    logic [NUM_PE-1:0] wgt_load_en;
    logic              wgt_load_bank;

    assign queued_launch = (matrix_counter == '0) && buffer_valid[read_bank];
    assign in_ready = !buffer_valid[active_bank] || (queued_launch && (active_bank == read_bank));
    assign accept_event = in_valid && in_ready;
    assign direct_launch = (matrix_counter == '0) && !queued_launch && accept_event;
    assign launch_event  = queued_launch || direct_launch;
    assign launch_bank   = direct_launch ? active_bank : read_bank;
    assign buffer_write  = accept_event && !direct_launch;

    // pe_array input routing
    always_comb begin
        arr_a_valid  = '0;
        arr_a_bank   = '0;
        arr_a_in     = '{default:'0};
        arr_a_row    = '{default:'0};
        arr_b_in     = '{default:'0};
        wgt_load_en  = '0;
        wgt_load_bank = 1'b0;

        // activation routing
        for (int lane = 0; lane < NUM_PE; lane++) begin
            arr_a_valid[lane] = a_valid_pipe[lane][0];
            arr_a_bank[lane]  = a_bank_pipe[lane][0];
            arr_a_in[lane]    = a_data_pipe[lane][0];
            arr_a_row[lane]   = a_row_pipe[lane][0];
        end

        // weight routing
        for (int col = 0; col < NUM_PE; col++) begin
            arr_b_in[col]    = wgt_data_pipe[col][0];
            wgt_load_en[col] = wgt_load_pipe[col][0];
            if (wgt_load_pipe[col][0])
                wgt_load_bank = wgt_bank_pipe[col][0];
        end
    end

    // Collect valid results from the systolic array into the C buffer.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            c_buffer <= '{default:'0};
        end else begin
            // Control & collect every valid result.
            for (int col = 0; col < NUM_PE; col++) begin
                if (arr_c_valid[col]) begin
                c_buffer[arr_c_bank[col]][arr_c_row[col]][col] <= arr_c_out[col];
                end
            end
        end
    end

    // Expose the completion pulse without another output register.  Buffered
    // cells form the matrix, while any matching live array result bypasses
    // c_buffer during this same valid cycle.
    always_comb begin
        out_valid = done_valid_pipe[0];

        for (int row = 0; row < NUM_PE; row++) begin
            for (int col = 0; col < NUM_PE; col++) begin
                if (arr_c_valid[col] &&
                   (arr_c_bank[col] == done_bank_pipe[0]) &&
                   (arr_c_row[col] == row)) begin
                    c_out[row][col] = arr_c_out[col];
                end else begin
                    c_out[row][col] = c_buffer[done_bank_pipe[0]][row][col];
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            done_valid_pipe <= '{default:'0};
            done_bank_pipe  <= '{default:'0};
        end else begin
            for (int delay = 0; delay < DONE_DEPTH-1; delay++) begin
                done_valid_pipe[delay] <= done_valid_pipe[delay+1];
                done_bank_pipe[delay]  <= done_bank_pipe[delay+1];
            end
            done_valid_pipe[DONE_DEPTH-1] <= 1'b0;
            done_bank_pipe[DONE_DEPTH-1]  <= 1'b0;

            if (launch_event) begin
                done_valid_pipe[DONE_DELAY] <= 1'b1;
                done_bank_pipe[DONE_DELAY]  <= launch_bank;
            end
        end
    end
    
    // Input activation bank control & delay lines
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_data_pipe    <= '{default:'0};
            a_valid_pipe   <= '{default:'0};
            a_bank_pipe    <= '{default:'0};
            a_row_pipe     <= '{default:'0};
        end else begin
            for (int lane = 0; lane < NUM_PE; lane++) begin
                for (int delay = 0; delay < A_PIPE_DEPTH-1; delay++) begin
                    a_data_pipe[lane][delay]  <= a_data_pipe[lane][delay+1];
                    a_valid_pipe[lane][delay] <= a_valid_pipe[lane][delay+1];
                    a_bank_pipe[lane][delay]  <= a_bank_pipe[lane][delay+1];
                    a_row_pipe[lane][delay]   <= a_row_pipe[lane][delay+1];
                end
                a_data_pipe[lane][A_PIPE_DEPTH-1]  <= '0;
                a_valid_pipe[lane][A_PIPE_DEPTH-1] <= 1'b0;
                a_bank_pipe[lane][A_PIPE_DEPTH-1]  <= 1'b0;
                a_row_pipe[lane][A_PIPE_DEPTH-1]   <= '0;
            end

            if (launch_event) begin
                for (int lane = 0; lane < NUM_PE; lane++) begin
                    for (int row = 0; row < NUM_PE; row++) begin
                        if (direct_launch)
                            a_data_pipe[lane][NUM_PE+row+lane] <= a_in[row][lane];
                        else
                            a_data_pipe[lane][NUM_PE+row+lane] <= a_buffer[read_bank][row][lane];

                        a_valid_pipe[lane][NUM_PE+row+lane] <= 1'b1;
                        a_bank_pipe[lane][NUM_PE+row+lane]  <= launch_bank;
                        a_row_pipe[lane][NUM_PE+row+lane]   <= row;
                    end
                end
            end
        end
    end

    // Weight pre-loading bank control & delay lines
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wgt_data_pipe  <= '{default:'0};
            wgt_load_pipe  <= '{default:'0};
            wgt_bank_pipe  <= '{default:'0};
        end else begin
            for (int col = 0; col < NUM_PE; col++) begin
                for (int delay = 0; delay < W_PIPE_DEPTH-1; delay++) begin
                    wgt_data_pipe[col][delay] <= wgt_data_pipe[col][delay+1];
                    wgt_load_pipe[col][delay] <= wgt_load_pipe[col][delay+1];
                    wgt_bank_pipe[col][delay] <= wgt_bank_pipe[col][delay+1];
                end
                wgt_data_pipe[col][W_PIPE_DEPTH-1] <= '0;
                wgt_load_pipe[col][W_PIPE_DEPTH-1] <= 1'b0;
                wgt_bank_pipe[col][W_PIPE_DEPTH-1] <= 1'b0;
            end

            if (launch_event) begin
                for (int col = 0; col < NUM_PE; col++) begin
                    for (int row = 0; row < NUM_PE; row++) begin
                        if (direct_launch)
                            wgt_data_pipe[col][NUM_PE-1-row+col] <= b_in[row][col];
                        else
                            wgt_data_pipe[col][NUM_PE-1-row+col] <= b_buffer[read_bank][row][col];
                    end
                    wgt_load_pipe[col][NUM_PE-1+col] <= 1'b1;
                    wgt_bank_pipe[col][NUM_PE-1+col] <= launch_bank;
                end
            end
        end
    end

    // Active bank rotation control.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active_bank    <= 1'b0;
        end else begin
            if (accept_event) active_bank <= ~active_bank;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            read_bank      <= 1'b0;
        end else begin
            if (queued_launch) begin
                read_bank <= ~read_bank;
            end else if (direct_launch) begin
                read_bank <= ~read_bank;
            end
        end
    end

    // Input activation & weight pre-loading buffers.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            buffer_valid   <= '0;
            a_buffer       <= '{default:'0};
            b_buffer       <= '{default:'0};
        end else begin
            if (queued_launch) begin
                buffer_valid[read_bank] <= 1'b0;
            end

            if (buffer_write) begin
                a_buffer[active_bank]     <= a_in;
                b_buffer[active_bank]     <= b_in;
                buffer_valid[active_bank] <= 1'b1;
            end
        end
    end

    // flow control counter for matrix launch events.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            matrix_counter <= '0;
        end else begin
            if (launch_event)
                matrix_counter <= NUM_PE-1;
            else if (matrix_counter != '0)
                matrix_counter <= matrix_counter - 1'b1;
        end
    end

    pe_array #(
        .DATA_WIDTH(DATA_WIDTH),
        .PSUM_WIDTH(PSUM_WIDTH),
        .NUM_PE(NUM_PE),
        .ROW_WIDTH(ROW_WIDTH)
    ) pe_array_inst (
        .clk          (clk),
        .rst_n        (rst_n),
        .wgt_load_en  (wgt_load_en),
        .wgt_load_bank(wgt_load_bank),
        .a_valid      (arr_a_valid),
        .a_bank       (arr_a_bank),
        .a_row        (arr_a_row),
        .a_in         (arr_a_in),
        .b_in         (arr_b_in),
        .c_valid      (arr_c_valid),
        .c_bank       (arr_c_bank),
        .c_row        (arr_c_row),
        .c_out        (arr_c_out)
    );

endmodule
