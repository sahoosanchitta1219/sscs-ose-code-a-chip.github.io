`timescale 1ns / 1ps

module controller #(
    parameter TILE_SIZE = 16
)(
    input  wire clk,
    input  wire rst_n,
    input  wire tile_valid,
    input  wire is_zero,
    input  wire use_sparse,

    output reg  [$clog2(TILE_SIZE)-1:0] rd_addr,
    output reg  [$clog2(TILE_SIZE+1)-1:0] zero_count,
    output reg  mode_latched,  // 0: Dense, 1: Sparse
    output reg  mac_en,
    output reg  acc_en,
    output reg  acc_clr,
    output reg  done
);

    localparam S_IDLE  = 2'b00,
               S_SCAN  = 2'b01,
               S_EVAL  = 2'b10,
               S_COMP  = 2'b11;

    reg [1:0] state, next_state;
    reg [$clog2(TILE_SIZE)-1:0] ptr;

    reg done_internal;

    // Direct combinational MAC enable based on current element at rd_addr
    always @(*) begin
        if (state == S_COMP) begin
            if (!mode_latched) begin
                mac_en = 1'b1;
            end else begin
                mac_en = !is_zero;
            end
        end else begin
            mac_en = 1'b0;
        end
    end

    // FSM State Register
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= S_IDLE;
        else state <= next_state;
    end

    // Next State Logic
    always @(*) begin
        case (state)
            S_IDLE: next_state = tile_valid ? S_SCAN : S_IDLE;
            S_SCAN: next_state = (ptr == TILE_SIZE - 1) ? S_EVAL : S_SCAN;
            S_EVAL: next_state = S_COMP;
            S_COMP: next_state = (ptr == TILE_SIZE - 1) ? S_IDLE : S_COMP;
            default: next_state = S_IDLE;
        endcase
    end

    // Counter & Control Signals
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ptr           <= 0;
            zero_count    <= 0;
            mode_latched  <= 0;
            rd_addr       <= 0;
            acc_en        <= 0;
            acc_clr       <= 0;
            done          <= 0;
            done_internal <= 0;
        end else begin
            acc_en        <= mac_en; // acc_en is EXACT 1-cycle delayed copy of mac_en
            acc_clr       <= 0;
            done          <= done_internal;
            done_internal <= 0;

            case (state)
                S_IDLE: begin
                    ptr        <= 0;
                    zero_count <= 0;
                    rd_addr    <= 0;
                    if (tile_valid) acc_clr <= 1'b1;
                end

                S_SCAN: begin
                    if (is_zero) zero_count <= zero_count + 1'b1;
                    if (ptr == TILE_SIZE - 1) begin
                        ptr     <= 0;
                        rd_addr <= 0;
                    end else begin
                        ptr     <= ptr + 1'b1;
                        rd_addr <= ptr + 1'b1;
                    end
                end

                S_EVAL: begin
                    mode_latched <= use_sparse;
                    ptr          <= 0;
                    rd_addr      <= 0;
                end

                S_COMP: begin
                    if (ptr < TILE_SIZE - 1) begin
                        rd_addr <= ptr + 1'b1;
                        ptr     <= ptr + 1'b1;
                    end else begin
                        ptr           <= 0;
                        done_internal <= 1'b1;
                    end
                end
            endcase
        end
    end

endmodule
