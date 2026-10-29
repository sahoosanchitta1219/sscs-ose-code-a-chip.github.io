`timescale 1ns / 1ps

module input_buffer #(
    parameter TILE_SIZE  = 16,
    parameter DATA_WIDTH = 8
)(
    input  wire clk,
    input  wire wr_en,
    input  wire [$clog2(TILE_SIZE)-1:0] wr_addr,
    input  wire signed [DATA_WIDTH-1:0] act_in,
    input  wire signed [DATA_WIDTH-1:0] wt_in,

    input  wire [$clog2(TILE_SIZE)-1:0] rd_addr,
    output wire signed [DATA_WIDTH-1:0] act_out,
    output wire signed [DATA_WIDTH-1:0] wt_out
);

    reg signed [DATA_WIDTH-1:0] act_mem [0:TILE_SIZE-1];
    reg signed [DATA_WIDTH-1:0] wt_mem  [0:TILE_SIZE-1];

    always @(posedge clk) begin
        if (wr_en) begin
            act_mem[wr_addr] <= act_in;
            wt_mem[wr_addr]  <= wt_in;
        end
    end

    assign act_out = act_mem[rd_addr];
    assign wt_out  = wt_mem[rd_addr];

endmodule
