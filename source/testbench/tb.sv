`timescale 1ns/1ps

module tb_systolic_top;
    localparam int DATA_WIDTH       = 4;
    localparam int PSUM_WIDTH       = 9;
    localparam int NUM_PE          = 3;
    localparam int CLK_PERIOD      = 10;
    localparam int FIRST_LATENCY   = 4*NUM_PE-1;
    localparam int MAX_TEST_CYCLES = 1000;

    localparam int DIRECTED_JOBS   = 2;
    localparam int STREAM_JOBS     = 4;
    localparam int CORNER_JOBS     = 2;
    localparam int RANDOM_JOBS     = 50;
    localparam int SPECIAL_JOBS    = 11;
    localparam int TOTAL_JOBS      = DIRECTED_JOBS + STREAM_JOBS +
                                     CORNER_JOBS + RANDOM_JOBS +
                                     SPECIAL_JOBS;

    localparam int MAX_CORNER_JOB  = DIRECTED_JOBS + STREAM_JOBS;
    localparam int MIN_CORNER_JOB  = MAX_CORNER_JOB + 1;
    localparam int RANDOM_BASE_JOB = MIN_CORNER_JOB + 1;
    localparam int MAX_PATTERN_JOB = RANDOM_BASE_JOB + RANDOM_JOBS;
    localparam int ZERO_JOB        = MAX_PATTERN_JOB + 1;
    localparam int IDENTITY_JOB    = ZERO_JOB + 1;
    localparam int ONES_JOB        = IDENTITY_JOB + 1;
    localparam int SIGNED_MAX_JOB  = ONES_JOB + 1;
    localparam int SIGNED_MIN_JOB  = SIGNED_MAX_JOB + 1;
    localparam int ZERO_PROP_JOB   = SIGNED_MIN_JOB + 1;
    localparam int NONCOMM_AB_JOB  = ZERO_PROP_JOB + 1;
    localparam int NONCOMM_BA_JOB  = NONCOMM_AB_JOB + 1;
    localparam int LINEAR_BASE_JOB = NONCOMM_BA_JOB + 1;
    localparam int LINEAR_2A_JOB   = LINEAR_BASE_JOB + 1;

    localparam int CAT_DIRECTED     = 0;
    localparam int CAT_RANDOM       = 1;
    localparam int CAT_MAX_RESULT   = 2;
    localparam int CAT_MIN_RESULT   = 3;
    localparam int CAT_F_PATTERN    = 4;
    localparam int CAT_ZERO_MATRIX  = 5;
    localparam int CAT_IDENTITY     = 6;
    localparam int CAT_ONES         = 7;
    localparam int CAT_SIGNED_MAX   = 8;
    localparam int CAT_SIGNED_MIN   = 9;
    localparam int CAT_ZERO_PROP    = 10;
    localparam int CAT_NONCOMM      = 11;
    localparam int CAT_LINEAR       = 12;
    localparam int CATEGORY_COUNT   = 13;

    localparam int PROP_IDENTITY    = 0;
    localparam int PROP_ZERO        = 1;
    localparam int PROP_NONCOMM     = 2;
    localparam int PROP_LINEAR      = 3;
    localparam int PROPERTY_COUNT   = 4;

    // TOTAL_JOBS is odd, so the final matrix uses bank 0 and the preceding
    // matrix uses bank 1.
    localparam int LAST_BANK0_JOB  = TOTAL_JOBS-1;
    localparam int LAST_BANK1_JOB  = TOTAL_JOBS-2;

    logic clk;
    logic rst_n;
    logic in_valid;
    logic in_ready;
    logic out_valid;
    logic signed [DATA_WIDTH-1:0]
        a_in [NUM_PE-1:0][NUM_PE-1:0];
    logic signed [DATA_WIDTH-1:0]
        b_in [NUM_PE-1:0][NUM_PE-1:0];
    logic signed [PSUM_WIDTH-1:0]
        c_out [NUM_PE-1:0][NUM_PE-1:0];

    logic signed [DATA_WIDTH-1:0]
        test_a [TOTAL_JOBS-1:0][NUM_PE-1:0][NUM_PE-1:0];
    logic signed [DATA_WIDTH-1:0]
        test_b [TOTAL_JOBS-1:0][NUM_PE-1:0][NUM_PE-1:0];
    integer expected
        [TOTAL_JOBS-1:0][NUM_PE-1:0][NUM_PE-1:0];

    integer errors;
    integer cycle_number;
    integer accepted_count;
    integer launch_count;
    integer activation_count;
    integer output_count;
    integer first_accept_cycle;
    integer first_output_cycle;
    integer previous_output_cycle;
    integer matrix_passes;
    integer matrix_failures;
    integer property_passes;
    integer property_failures;
    integer property_mismatches;
    integer property_differences;
    integer category_passes [CATEGORY_COUNT-1:0];
    integer category_failures [CATEGORY_COUNT-1:0];
    integer property_category_passes [PROPERTY_COUNT-1:0];
    integer property_category_failures [PROPERTY_COUNT-1:0];

    systolic_top #(
        .DATA_WIDTH(DATA_WIDTH),
        .PSUM_WIDTH(PSUM_WIDTH),
        .NUM_PE(NUM_PE)
    ) dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .in_valid (in_valid),
        .in_ready (in_ready),
        .a_in     (a_in),
        .b_in     (b_in),
        .out_valid(out_valid),
        .c_out    (c_out)
    );

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    always @(posedge clk)
        cycle_number++;

    task automatic calculate_expected;
        begin
            for (int job = 0; job < TOTAL_JOBS; job++) begin
                for (int row = 0; row < NUM_PE; row++) begin
                    for (int col = 0; col < NUM_PE; col++) begin
                        expected[job][row][col] = 0;
                        for (int k = 0; k < NUM_PE; k++) begin
                            expected[job][row][col] +=
                                $signed(test_a[job][row][k]) *
                                $signed(test_b[job][k][col]);
                        end
                    end
                end
            end
        end
    endtask

    function automatic string test_name(input integer job);
        if (job < DIRECTED_JOBS)
            return "Directed signed arithmetic";
        else if (job < DIRECTED_JOBS+STREAM_JOBS)
            return "Continuous-stream random";
        else if (job == MAX_CORNER_JOB)
            return "Maximum result: (-8)x(-8)";
        else if (job == MIN_CORNER_JOB)
            return "Minimum result: (-8)x(+7)";
        else if (job < RANDOM_BASE_JOB+RANDOM_JOBS)
            return "Random matrix";
        else if (job == MAX_PATTERN_JOB)
            return "All 4'hf bit pattern (signed -1)";
        else if (job == ZERO_JOB)
            return "All-zero matrices";
        else if (job == IDENTITY_JOB)
            return "Identity property: A x I = A";
        else if (job == ONES_JOB)
            return "All-ones matrices";
        else if (job == SIGNED_MAX_JOB)
            return "Signed maximum matrices (+7)";
        else if (job == SIGNED_MIN_JOB)
            return "Signed minimum matrices (-8)";
        else if (job == ZERO_PROP_JOB)
            return "Zero property: A x 0 = 0";
        else if (job == NONCOMM_AB_JOB)
            return "Non-commutativity: A x B";
        else if (job == NONCOMM_BA_JOB)
            return "Non-commutativity: B x A";
        else if (job == LINEAR_BASE_JOB)
            return "Scalar linearity baseline: A x B";
        else if (job == LINEAR_2A_JOB)
            return "Scalar linearity: (2A) x B";
        else
            return "Unknown";
    endfunction

    function automatic string test_attribute(input integer job);
        if (job < DIRECTED_JOBS)
            return "Verifies signed MAC arithmetic, negative operands, and bank handoff.";
        else if (job < DIRECTED_JOBS+STREAM_JOBS)
            return "Verifies bubble-free ready/valid streaming across matrix boundaries.";
        else if (job == MAX_CORNER_JOB)
            return "Verifies the largest 3-term signed result: 3*(-8)*(-8) = +192.";
        else if (job == MIN_CORNER_JOB)
            return "Verifies the smallest 3-term signed result: 3*(-8)*(+7) = -168.";
        else if (job < RANDOM_BASE_JOB+RANDOM_JOBS)
            return "Verifies general signed matrix multiplication with randomized 4-bit data.";
        else if (job == MAX_PATTERN_JOB)
            return "Verifies the 4'hf bit pattern is interpreted as signed -1, not unsigned 15.";
        else if (job == ZERO_JOB)
            return "Verifies 0 x 0 produces an entirely zero output matrix.";
        else if (job == IDENTITY_JOB)
            return "Verifies the identity property: A x I must reproduce A exactly.";
        else if (job == ONES_JOB)
            return "Verifies accumulation of three unit products; every C element must equal 3.";
        else if (job == SIGNED_MAX_JOB)
            return "Verifies all maximum signed inputs (+7); every C element must equal 147.";
        else if (job == SIGNED_MIN_JOB)
            return "Verifies all minimum signed inputs (-8); every C element must equal 192.";
        else if (job == ZERO_PROP_JOB)
            return "Verifies the zero property: an arbitrary A multiplied by zero must be zero.";
        else if (job == NONCOMM_AB_JOB)
            return "First half of the non-commutativity check; compare with the following B x A case.";
        else if (job == NONCOMM_BA_JOB)
            return "Verifies matrix order matters: this B x A result must differ from A x B.";
        else if (job == LINEAR_BASE_JOB)
            return "Establishes baseline C=A x B for the following scalar-linearity comparison.";
        else if (job == LINEAR_2A_JOB)
            return "Verifies scalar linearity: (2A) x B must equal 2 times the baseline C.";
        else
            return "No verification attribute is defined for this matrix.";
    endfunction

    function automatic integer matrix_category(input integer job);
        if (job < DIRECTED_JOBS)
            return CAT_DIRECTED;
        else if ((job < DIRECTED_JOBS+STREAM_JOBS) ||
                 ((job >= RANDOM_BASE_JOB) &&
                  (job < RANDOM_BASE_JOB+RANDOM_JOBS)))
            return CAT_RANDOM;
        else if (job == MAX_CORNER_JOB)
            return CAT_MAX_RESULT;
        else if (job == MIN_CORNER_JOB)
            return CAT_MIN_RESULT;
        else if (job == MAX_PATTERN_JOB)
            return CAT_F_PATTERN;
        else if (job == ZERO_JOB)
            return CAT_ZERO_MATRIX;
        else if (job == IDENTITY_JOB)
            return CAT_IDENTITY;
        else if (job == ONES_JOB)
            return CAT_ONES;
        else if (job == SIGNED_MAX_JOB)
            return CAT_SIGNED_MAX;
        else if (job == SIGNED_MIN_JOB)
            return CAT_SIGNED_MIN;
        else if (job == ZERO_PROP_JOB)
            return CAT_ZERO_PROP;
        else if ((job == NONCOMM_AB_JOB) || (job == NONCOMM_BA_JOB))
            return CAT_NONCOMM;
        else
            return CAT_LINEAR;
    endfunction

    function automatic string category_name(input integer category);
        case (category)
            CAT_DIRECTED:    return "Directed signed arithmetic";
            CAT_RANDOM:      return "Random matrices";
            CAT_MAX_RESULT:  return "Maximum result corner";
            CAT_MIN_RESULT:  return "Minimum result corner";
            CAT_F_PATTERN:   return "All 4'hf pattern";
            CAT_ZERO_MATRIX: return "All-zero matrices";
            CAT_IDENTITY:    return "Identity matrix";
            CAT_ONES:        return "All-one matrices";
            CAT_SIGNED_MAX:  return "Signed maximum (+7)";
            CAT_SIGNED_MIN:  return "Signed minimum (-8)";
            CAT_ZERO_PROP:   return "Zero property matrices";
            CAT_NONCOMM:     return "Non-commutativity matrices";
            CAT_LINEAR:      return "Scalar-linearity matrices";
            default:         return "Unknown";
        endcase
    endfunction

    function automatic string property_name(input integer property_id);
        case (property_id)
            PROP_IDENTITY: return "Identity: A x I = A";
            PROP_ZERO:     return "Zero: A x 0 = 0";
            PROP_NONCOMM:  return "Non-Commutativity: A x B != B x A";
            PROP_LINEAR:   return "Scalar Linearity: (2A)xB = 2C";
            default:       return "Unknown";
        endcase
    endfunction

    task automatic record_matrix_category(
        input integer job,
        input logic passed
    );
        integer category;
        begin
            category = matrix_category(job);
            if (passed)
                category_passes[category]++;
            else
                category_failures[category]++;
        end
    endtask

    task automatic display_category_summary;
        integer category_total;
        integer property_total;
        begin
            $display("\n================ FUNCTIONALITY BY CATEGORY ================");
            $display("  %-34s %7s %7s %7s", "Category", "Total", "Passed", "Failed");
            $display("  ---------------------------------------------------------");
            for (int category = 0; category < CATEGORY_COUNT; category++) begin
                category_total = category_passes[category] +
                                 category_failures[category];
                $display("  %-34s %7d %7d %7d", category_name(category),
                         category_total, category_passes[category],
                         category_failures[category]);
            end

            $display("\n================== ALGEBRAIC PROPERTIES ===================");
            $display("  %-40s %5s %7s %7s", "Property", "Total", "Passed", "Failed");
            $display("  ---------------------------------------------------------");
            for (int property_id = 0; property_id < PROPERTY_COUNT;
                 property_id++) begin
                property_total = property_category_passes[property_id] +
                                 property_category_failures[property_id];
                $display("  %-40s %5d %7d %7d",
                         property_name(property_id), property_total,
                         property_category_passes[property_id],
                         property_category_failures[property_id]);
            end
            $display("===========================================================\n");
        end
    endtask

    task automatic display_matrix_result(
        input integer job,
        input logic passed
    );
        begin
            $display("\n===============================================================================================");
            $display("TESTCASE %0d: %s", job, test_name(job));
            $display("ATTRIBUTE   : %s", test_attribute(job));
            $display("-----------------------------------------------------------------------------------------------");
            $display("       Matrix A             Matrix B             Golden C=A*B          RTL C");
            $display("  +-----------------+  +-----------------+  +-----------------+  +-----------------+");
            for (int row = 0; row < NUM_PE; row++) begin
                $display("  | %4d %4d %4d |  | %4d %4d %4d |  | %4d %4d %4d |  | %4d %4d %4d |",
                         $signed(test_a[job][row][0]),
                         $signed(test_a[job][row][1]),
                         $signed(test_a[job][row][2]),
                         $signed(test_b[job][row][0]),
                         $signed(test_b[job][row][1]),
                         $signed(test_b[job][row][2]),
                         expected[job][row][0],
                         expected[job][row][1],
                         expected[job][row][2],
                         $signed(c_out[row][0]),
                         $signed(c_out[row][1]),
                         $signed(c_out[row][2]));
            end
            $display("  +-----------------+  +-----------------+  +-----------------+  +-----------------+");
            if (passed)
                $display("RESULT      : PASS -- RTL output matches the golden matrix.");
            else
                $display("RESULT      : FAIL -- inspect the Golden C and RTL C columns above.");
            $display("===============================================================================================\n");
        end
    endtask

    // This is a continuous ready/valid producer.  in_valid never drops
    // between matrices.  When in_ready is low, the current matrix remains
    // stable until the DUT accepts it.
    task automatic drive_continuous_stream;
        integer job;
        begin
            job = 0;

            @(negedge clk);
            a_in     = test_a[0];
            b_in     = test_b[0];
            in_valid = 1'b1;

            while (job < TOTAL_JOBS) begin
                @(posedge clk);
                if (in_ready === 1'b1) begin
                    #1;
                    if (job == 0)
                        first_accept_cycle = cycle_number;
                    accepted_count++;
                    job++;

                    @(negedge clk);
                    if (job < TOTAL_JOBS) begin
                        a_in = test_a[job];
                        b_in = test_b[job];
                    end else begin
                        in_valid = 1'b0;
                    end
                end else begin
                    @(negedge clk);
                end
            end
        end
    endtask

    // Every matrix must launch exactly NUM_PE clocks after the previous one.
    // The bank bit must alternate for the complete, unbounded stream.
    task automatic monitor_launches;
        integer observed_cycles;
        time previous_launch_time;
        begin
            observed_cycles = 0;
            previous_launch_time = 0;

            while ((launch_count < TOTAL_JOBS) &&
                   (observed_cycles < MAX_TEST_CYCLES)) begin
                @(posedge clk);
                observed_cycles++;
                if (dut.launch_event === 1'b1) begin
                    if ((launch_count != 0) &&
                        ((($time-previous_launch_time)/CLK_PERIOD) !=
                         NUM_PE)) begin
                        $error("matrix %0d launch gap=%0d, expected=%0d",
                               launch_count,
                               ($time-previous_launch_time)/CLK_PERIOD,
                               NUM_PE);
                        errors++;
                    end

                    if (dut.launch_bank !== launch_count[0]) begin
                        $error("matrix %0d launched on bank %0b, expected %0b",
                               launch_count, dut.launch_bank,
                               launch_count[0]);
                        errors++;
                    end

                    previous_launch_time = $time;
                    launch_count++;
                end
            end

            if (launch_count != TOTAL_JOBS) begin
                $error("observed %0d of %0d matrix launches",
                       launch_count, TOTAL_JOBS);
                errors++;
            end
        end
    endtask

    // Lane 0 carries NUM_PE rows per matrix.  Once its first activation
    // arrives, valid must remain high for all TOTAL_JOBS*NUM_PE clocks.  This
    // directly detects a bubble at every matrix boundary, including 2->3.
    task automatic monitor_continuous_activations;
        integer observed_cycles;
        integer job;
        integer row;
        logic stream_started;
        begin
            observed_cycles = 0;
            stream_started = 1'b0;

            while ((activation_count < TOTAL_JOBS*NUM_PE) &&
                   (observed_cycles < MAX_TEST_CYCLES)) begin
                @(negedge clk);
                observed_cycles++;

                if (!stream_started && (dut.arr_a_valid[0] === 1'b1))
                    stream_started = 1'b1;

                if (stream_started) begin
                    if (dut.arr_a_valid[0] !== 1'b1) begin
                        $error("activation bubble after sample %0d",
                               activation_count-1);
                        errors++;
                    end else begin
                        job = activation_count / NUM_PE;
                        row = activation_count % NUM_PE;

                        if (dut.arr_a_bank[0] !== job[0]) begin
                            $error("activation job %0d bank=%0b expected=%0b",
                                   job, dut.arr_a_bank[0], job[0]);
                            errors++;
                        end
                        if (dut.arr_a_row[0] != row) begin
                            $error("activation job %0d row=%0d expected=%0d",
                                   job, dut.arr_a_row[0], row);
                            errors++;
                        end
                        if ($signed(dut.arr_a_in[0]) !==
                            $signed(test_a[job][row][0])) begin
                            $error("activation job %0d row %0d data=%0d expected=%0d",
                                   job, row, $signed(dut.arr_a_in[0]),
                                   $signed(test_a[job][row][0]));
                            errors++;
                        end

                        activation_count++;
                    end
                end
            end

            if (activation_count != TOTAL_JOBS*NUM_PE) begin
                $error("observed %0d of %0d lane-0 activations",
                       activation_count, TOTAL_JOBS*NUM_PE);
                errors++;
            end
        end
    endtask

    task automatic monitor_outputs;
        integer observed_cycles;
        integer errors_before;
        begin
            observed_cycles = 0;

            while ((output_count < TOTAL_JOBS) &&
                   (observed_cycles < MAX_TEST_CYCLES)) begin
                @(posedge clk);
                #1;
                observed_cycles++;

                if (out_valid === 1'b1) begin
                    errors_before = errors;

                    if (output_count == 0) begin
                        first_output_cycle = cycle_number;
                        if ((cycle_number-first_accept_cycle) !=
                            FIRST_LATENCY) begin
                            $error("first output latency=%0d expected=%0d",
                                   cycle_number-first_accept_cycle,
                                   FIRST_LATENCY);
                            errors++;
                        end
                    end else if ((cycle_number-previous_output_cycle) !=
                                 NUM_PE) begin
                        $error("matrix %0d output gap=%0d expected=%0d",
                               output_count,
                               cycle_number-previous_output_cycle,
                               NUM_PE);
                        errors++;
                    end

                    for (int row = 0; row < NUM_PE; row++) begin
                        for (int col = 0; col < NUM_PE; col++) begin
                            if ($signed(c_out[row][col]) !==
                                expected[output_count][row][col]) begin
                                $error("matrix %0d C[%0d][%0d]=%0d expected=%0d",
                                       output_count, row, col,
                                       $signed(c_out[row][col]),
                                       expected[output_count][row][col]);
                                errors++;
                            end
                        end
                    end

                    if (errors == errors_before) begin
                        $display("PASS matrix %0d", output_count);
                        matrix_passes++;
                        record_matrix_category(output_count, 1'b1);
                        display_matrix_result(output_count, 1'b1);
                    end else begin
                        matrix_failures++;
                        record_matrix_category(output_count, 1'b0);
                        display_matrix_result(output_count, 1'b0);
                    end

                    previous_output_cycle = cycle_number;
                    output_count++;
                end
            end

            if (output_count != TOTAL_JOBS) begin
                $error("observed %0d of %0d output matrices",
                       output_count, TOTAL_JOBS);
                errors++;
            end
        end
    endtask

    `define CHECK_FINAL_WEIGHT_BANKS(ROW, COL) \
        if ($signed(dut.pe_array_inst.gen_row[ROW].gen_col[COL].pe_inst.wgt_buf0) \
            !== $signed(test_b[LAST_BANK0_JOB][ROW][COL])) begin \
            $error("PE[%0d][%0d] bank0=%0d expected=%0d", ROW, COL, \
                   $signed(dut.pe_array_inst.gen_row[ROW].gen_col[COL].pe_inst.wgt_buf0), \
                   $signed(test_b[LAST_BANK0_JOB][ROW][COL])); \
            errors++; \
        end \
        if ($signed(dut.pe_array_inst.gen_row[ROW].gen_col[COL].pe_inst.wgt_buf1) \
            !== $signed(test_b[LAST_BANK1_JOB][ROW][COL])) begin \
            $error("PE[%0d][%0d] bank1=%0d expected=%0d", ROW, COL, \
                   $signed(dut.pe_array_inst.gen_row[ROW].gen_col[COL].pe_inst.wgt_buf1), \
                   $signed(test_b[LAST_BANK1_JOB][ROW][COL])); \
            errors++; \
        end

    task automatic check_final_weight_banks;
        begin
            `CHECK_FINAL_WEIGHT_BANKS(0, 0)
            `CHECK_FINAL_WEIGHT_BANKS(0, 1)
            `CHECK_FINAL_WEIGHT_BANKS(0, 2)
            `CHECK_FINAL_WEIGHT_BANKS(1, 0)
            `CHECK_FINAL_WEIGHT_BANKS(1, 1)
            `CHECK_FINAL_WEIGHT_BANKS(1, 2)
            `CHECK_FINAL_WEIGHT_BANKS(2, 0)
            `CHECK_FINAL_WEIGHT_BANKS(2, 1)
            `CHECK_FINAL_WEIGHT_BANKS(2, 2)
        end
    endtask

    initial begin
        errors                = 0;
        cycle_number          = 0;
        accepted_count        = 0;
        launch_count          = 0;
        activation_count      = 0;
        output_count          = 0;
        first_accept_cycle    = 0;
        first_output_cycle    = 0;
        previous_output_cycle = 0;
        matrix_passes          = 0;
        matrix_failures        = 0;
        property_passes        = 0;
        property_failures      = 0;
        property_mismatches    = 0;
        property_differences   = 0;
        category_passes        = '{default:0};
        category_failures      = '{default:0};
        property_category_passes   = '{default:0};
        property_category_failures = '{default:0};
        rst_n                 = 1'b0;
        in_valid              = 1'b0;
        a_in                  = '{default:'0};
        b_in                  = '{default:'0};
        test_a                = '{default:'0};
        test_b                = '{default:'0};

        // Two deterministic matrices exercise signed arithmetic and the
        // first bank handoff.
        test_a[0] = '{'{ 1,-2, 3},
                      '{-4, 5,-6},
                      '{ 7,-1, 2}};
        test_b[0] = '{'{-1, 2,-3},
                      '{ 4,-1, 2},
                      '{-2, 3, 1}};

        test_a[1] = '{'{-8, 7,-1},
                      '{ 3,-4, 6},
                      '{ 0,-2, 5}};
        test_b[1] = '{'{ 7,-8, 1},
                      '{-3, 2,-7},
                      '{ 4,-1,-2}};

        // Four consecutive random matrices explicitly cover transitions
        // 1->2, 2->3, and 3->4 without ending the stream.
        for (int job = DIRECTED_JOBS;
             job < DIRECTED_JOBS+STREAM_JOBS; job++) begin
            for (int row = 0; row < NUM_PE; row++) begin
                for (int col = 0; col < NUM_PE; col++) begin
                    test_a[job][row][col] = $urandom_range(15, 0);
                    test_b[job][row][col] = $urandom_range(15, 0);
                end
            end
        end

        // Signed maximum and minimum results:
        //   3*(-8)*(-8) = +192
        //   3*(-8)*(+7) = -168
        for (int row = 0; row < NUM_PE; row++) begin
            for (int col = 0; col < NUM_PE; col++) begin
                test_a[MAX_CORNER_JOB][row][col] = -8;
                test_b[MAX_CORNER_JOB][row][col] = -8;
                test_a[MIN_CORNER_JOB][row][col] = -8;
                test_b[MIN_CORNER_JOB][row][col] =  7;
            end
        end

        // Preserve the fifty-matrix randomized regression, but place every
        // case in the same continuous stream instead of sending pairs.
        for (int job = RANDOM_BASE_JOB;
             job < RANDOM_BASE_JOB+RANDOM_JOBS; job++) begin
            for (int row = 0; row < NUM_PE; row++) begin
                for (int col = 0; col < NUM_PE; col++) begin
                    test_a[job][row][col] = $urandom_range(15, 0);
                    test_b[job][row][col] = $urandom_range(15, 0);
                end
            end
        end

        // 4'hf is signed -1, followed by all-zero and identity cases.
        for (int row = 0; row < NUM_PE; row++) begin
            for (int col = 0; col < NUM_PE; col++) begin
                test_a[MAX_PATTERN_JOB][row][col] = 4'hf;
                test_b[MAX_PATTERN_JOB][row][col] = 4'hf;
                test_a[ZERO_JOB][row][col] = 4'h0;
                test_b[ZERO_JOB][row][col] = 4'h0;
                test_a[IDENTITY_JOB][row][col] = $urandom_range(15, 0);
                test_b[IDENTITY_JOB][row][col] =
                    (row == col) ? 4'h1 : 4'h0;
            end
        end

        // Numeric all-ones, signed maximum, signed minimum, and A x 0.
        for (int row = 0; row < NUM_PE; row++) begin
            for (int col = 0; col < NUM_PE; col++) begin
                test_a[ONES_JOB][row][col]       =  1;
                test_b[ONES_JOB][row][col]       =  1;
                test_a[SIGNED_MAX_JOB][row][col] =  7;
                test_b[SIGNED_MAX_JOB][row][col] =  7;
                test_a[SIGNED_MIN_JOB][row][col] = -8;
                test_b[SIGNED_MIN_JOB][row][col] = -8;
                test_a[ZERO_PROP_JOB][row][col]  = $urandom_range(15, 0);
                test_b[ZERO_PROP_JOB][row][col]  = 0;
            end
        end

        // A and B are deliberately asymmetric, so A x B != B x A.
        test_a[NONCOMM_AB_JOB] =
            '{'{1,2,0}, '{0,1,0}, '{0,0,1}};
        test_b[NONCOMM_AB_JOB] =
            '{'{1,0,0}, '{3,1,0}, '{0,0,1}};
        test_a[NONCOMM_BA_JOB] = test_b[NONCOMM_AB_JOB];
        test_b[NONCOMM_BA_JOB] = test_a[NONCOMM_AB_JOB];

        // Scalar-linearity pair with c=2.  Values are intentionally small
        // enough that neither the 4-bit operands nor 9-bit sums overflow.
        test_a[LINEAR_BASE_JOB] =
            '{'{1,-2, 3}, '{0,1,-1}, '{2,0,-3}};
        test_b[LINEAR_BASE_JOB] =
            '{'{1, 2, 0}, '{-1,1,2}, '{2,-2,1}};
        for (int row = 0; row < NUM_PE; row++) begin
            for (int col = 0; col < NUM_PE; col++) begin
                test_a[LINEAR_2A_JOB][row][col] =
                    2*$signed(test_a[LINEAR_BASE_JOB][row][col]);
                test_b[LINEAR_2A_JOB][row][col] =
                    test_b[LINEAR_BASE_JOB][row][col];
            end
        end

        calculate_expected();

        if (expected[MAX_CORNER_JOB][0][0] != 192) begin
            $error("maximum corner golden result is not +192");
            errors++;
        end
        if (expected[MIN_CORNER_JOB][0][0] != -168) begin
            $error("minimum corner golden result is not -168");
            errors++;
        end

        property_mismatches = 0;
        for (int row = 0; row < NUM_PE; row++) begin
            for (int col = 0; col < NUM_PE; col++) begin
                if (expected[IDENTITY_JOB][row][col] !=
                    $signed(test_a[IDENTITY_JOB][row][col]))
                    property_mismatches++;
            end
        end
        if (property_mismatches == 0) begin
            property_passes++;
            property_category_passes[PROP_IDENTITY]++;
            $display("[PROPERTY] Identity A x I = A: golden setup PASS");
        end else begin
            property_failures++;
            property_category_failures[PROP_IDENTITY]++;
            errors++;
            $error("[PROPERTY] Identity setup has %0d mismatches",
                   property_mismatches);
        end

        property_mismatches = 0;
        for (int row = 0; row < NUM_PE; row++) begin
            for (int col = 0; col < NUM_PE; col++) begin
                if (expected[ZERO_PROP_JOB][row][col] != 0)
                    property_mismatches++;
            end
        end
        if (property_mismatches == 0) begin
            property_passes++;
            property_category_passes[PROP_ZERO]++;
            $display("[PROPERTY] Zero A x 0 = 0: golden setup PASS");
        end else begin
            property_failures++;
            property_category_failures[PROP_ZERO]++;
            errors++;
            $error("[PROPERTY] Zero setup has %0d mismatches",
                   property_mismatches);
        end

        property_differences = 0;
        for (int row = 0; row < NUM_PE; row++) begin
            for (int col = 0; col < NUM_PE; col++) begin
                if (expected[NONCOMM_AB_JOB][row][col] !=
                    expected[NONCOMM_BA_JOB][row][col])
                    property_differences++;
            end
        end
        if (property_differences > 0) begin
            property_passes++;
            property_category_passes[PROP_NONCOMM]++;
            $display("[PROPERTY] Non-Commutativity A x B != B x A: golden setup PASS");
        end else begin
            property_failures++;
            property_category_failures[PROP_NONCOMM]++;
            errors++;
            $error("[PROPERTY] Non-Commutativity setup produced equal matrices");
        end

        property_mismatches = 0;
        for (int row = 0; row < NUM_PE; row++) begin
            for (int col = 0; col < NUM_PE; col++) begin
                if (expected[LINEAR_2A_JOB][row][col] !=
                    2*expected[LINEAR_BASE_JOB][row][col])
                    property_mismatches++;
            end
        end
        if (property_mismatches == 0) begin
            property_passes++;
            property_category_passes[PROP_LINEAR]++;
            $display("[PROPERTY] Scalar Linearity (2A)xB = 2(AB): golden setup PASS");
        end else begin
            property_failures++;
            property_category_failures[PROP_LINEAR]++;
            errors++;
            $error("[PROPERTY] Scalar-linearity setup has %0d mismatches",
                   property_mismatches);
        end

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        fork
            drive_continuous_stream();
            monitor_launches();
            monitor_continuous_activations();
            monitor_outputs();
        join

        check_final_weight_banks();

        if (accepted_count != TOTAL_JOBS) begin
            $error("accepted %0d of %0d input matrices",
                   accepted_count, TOTAL_JOBS);
            errors++;
        end

        $display("\n========== CONTINUOUS STREAM SUMMARY ==========");
        $display("  Matrices accepted : %0d", accepted_count);
        $display("  Matrices launched : %0d", launch_count);
        $display("  Matrices completed: %0d", output_count);
        $display("  Lane-0 samples    : %0d", activation_count);
        $display("  Launch interval   : %0d clocks", NUM_PE);
        $display("  Output interval   : %0d clocks", NUM_PE);
        $display("  Matrix passes     : %0d", matrix_passes);
        $display("  Matrix failures   : %0d", matrix_failures);
        $display("  Property passes   : %0d", property_passes);
        $display("  Property failures : %0d", property_failures);
        $display("  Total passes      : %0d", matrix_passes+property_passes);
        $display("  Total failures    : %0d", matrix_failures+property_failures);
        $display("  Raw error events  : %0d", errors);
        $display("===============================================\n");

        display_category_summary();

        if (errors == 0)
            $display("ALL %0d MATRICES PASSED WITH NO STREAMING GAP\n",
                     TOTAL_JOBS);
        else
            $fatal(1, "TEST FAILED WITH %0d ERROR(S)\n", errors);

        $finish;
    end

    initial begin
        $dumpfile("double_buffered_systolic.vcd");
        $dumpvars(0, tb_systolic_top);
    end

endmodule
