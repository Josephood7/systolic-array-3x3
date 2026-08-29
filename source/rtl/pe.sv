module pe #(
    parameter int DATA_WIDTH = 4,
    parameter int PSUM_WIDTH = 9,
    parameter int ROW_WIDTH  = 2
)(
    input  logic clk,
    input  logic rst_n,
    
    input  logic wgt_load_en,
    input  logic wgt_load_bank,

    input  logic                         act_valid_in,
    input  logic                         act_bank_in,
    input  logic [ROW_WIDTH-1:0]         act_row_in,
    input  logic signed [DATA_WIDTH-1:0] act_in,
    input  logic signed [DATA_WIDTH-1:0] wgt_in,
    input  logic signed [PSUM_WIDTH-1:0] psum_in,

    output logic                         act_valid_out,
    output logic                         act_bank_out,
    output logic [ROW_WIDTH-1:0]         act_row_out,
    output logic signed [DATA_WIDTH-1:0] act_out,
    output logic signed [DATA_WIDTH-1:0] wgt_out,
    output logic signed [PSUM_WIDTH-1:0] psum_out
);

    localparam int PRODUCT_WIDTH = 2 * DATA_WIDTH;

    logic signed [DATA_WIDTH-1:0] wgt_buf0, wgt_buf1;
    logic signed [DATA_WIDTH-1:0] active_wgt;
    logic signed [PRODUCT_WIDTH-1:0] product;
    logic signed [PSUM_WIDTH-1:0] product_extended;
    logic signed [PSUM_WIDTH-1:0] mac;

    assign active_wgt      = act_bank_in ? wgt_buf1 : wgt_buf0;
    assign product         = $signed(act_in) * $signed(active_wgt);
    assign product_extended = product;
    assign mac             = $signed(psum_in) + $signed(product_extended);

    // Weight double-buffering logic.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wgt_buf0 <= '0;
            wgt_buf1 <= '0;
        end else begin
            if (wgt_load_en) begin
                if (wgt_load_bank)
                    wgt_buf1 <= wgt_in;
                else
                    wgt_buf0 <= wgt_in;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wgt_out  <= '0;
        end else begin
            wgt_out <= wgt_in;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            act_valid_out <= 1'b0;
            act_bank_out  <= 1'b0;
            act_row_out   <= '0;
            act_out       <= '0;
            psum_out      <= '0;
        end else if (act_valid_in) begin
            act_valid_out <= 1'b1;
            act_bank_out  <= act_bank_in;
            act_row_out   <= act_row_in;
            act_out       <= act_in;
            psum_out      <= mac;
        end else begin
            act_valid_out <= 1'b0;
            act_bank_out  <= 1'b0;
            act_row_out   <= '0;
            act_out       <= '0;
            psum_out      <= '0;
        end
    end

endmodule
