module pe_array #(
    parameter int DATA_WIDTH = 4,
    parameter int PSUM_WIDTH = 9,
    parameter int NUM_PE     = 3,
    parameter int ROW_WIDTH  = (NUM_PE <= 1) ? 1 : $clog2(NUM_PE)
)(
    input  logic clk,
    input  logic rst_n,

    input  logic [NUM_PE-1:0] wgt_load_en,
    input  logic              wgt_load_bank,

    input  logic [NUM_PE-1:0]                 a_valid,
    input  logic [NUM_PE-1:0]                 a_bank,
    input  logic [ROW_WIDTH-1:0]              a_row [NUM_PE-1:0],
    input  logic signed [DATA_WIDTH-1:0]       a_in  [NUM_PE-1:0],
    input  logic signed [DATA_WIDTH-1:0]       b_in  [NUM_PE-1:0],

    output logic [NUM_PE-1:0]                 c_valid,
    output logic [NUM_PE-1:0]                 c_bank,
    output logic [ROW_WIDTH-1:0]              c_row [NUM_PE-1:0],
    output logic signed [PSUM_WIDTH-1:0]       c_out [NUM_PE-1:0]
);

    typedef struct packed {
        logic                          valid;
        logic                          bank;
        logic [ROW_WIDTH-1:0]          row_id;
        logic signed [DATA_WIDTH-1:0]  act;
        logic signed [DATA_WIDTH-1:0]  wgt;
        logic signed [PSUM_WIDTH-1:0]  psum;
    } pe_data_t;

    pe_data_t pe_in  [NUM_PE-1:0][NUM_PE-1:0];
    pe_data_t pe_out [NUM_PE-1:0][NUM_PE-1:0];

    for (genvar row = 0; row < NUM_PE; row++) begin : gen_row
        for (genvar col = 0; col < NUM_PE; col++) begin : gen_col
            assign pe_in[row][col].valid  = (col == 0) ? a_valid[row] : pe_out[row][col-1].valid;
            assign pe_in[row][col].bank   = (col == 0) ? a_bank[row]  : pe_out[row][col-1].bank;
            assign pe_in[row][col].row_id = (col == 0) ? a_row[row]   : pe_out[row][col-1].row_id;
            assign pe_in[row][col].act    = (col == 0) ? a_in[row]    : pe_out[row][col-1].act;
            assign pe_in[row][col].wgt    = (row == 0) ? b_in[col]    : pe_out[row-1][col].wgt;
            assign pe_in[row][col].psum   = (row == 0) ? '0           : pe_out[row-1][col].psum;

            pe #(
                .DATA_WIDTH(DATA_WIDTH),
                .PSUM_WIDTH(PSUM_WIDTH),
                .ROW_WIDTH (ROW_WIDTH)
            ) pe_inst (
                .clk          (clk),
                .rst_n        (rst_n),
                .wgt_load_en  (wgt_load_en[col]),
                .wgt_load_bank(wgt_load_bank),
                .act_valid_in (pe_in[row][col].valid),
                .act_bank_in  (pe_in[row][col].bank),
                .act_row_in   (pe_in[row][col].row_id),
                .act_in       (pe_in[row][col].act),
                .wgt_in       (pe_in[row][col].wgt),
                .psum_in      (pe_in[row][col].psum),
                .act_valid_out(pe_out[row][col].valid),
                .act_bank_out (pe_out[row][col].bank),
                .act_row_out  (pe_out[row][col].row_id),
                .act_out      (pe_out[row][col].act),
                .wgt_out      (pe_out[row][col].wgt),
                .psum_out     (pe_out[row][col].psum)
            );
        end
    end

    for (genvar col = 0; col < NUM_PE; col++) begin : gen_output
        assign c_valid[col] = pe_out[NUM_PE-1][col].valid;
        assign c_bank[col]  = pe_out[NUM_PE-1][col].bank;
        assign c_row[col]   = pe_out[NUM_PE-1][col].row_id;
        assign c_out[col]   = pe_out[NUM_PE-1][col].psum;
    end

endmodule
