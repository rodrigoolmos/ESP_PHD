module test_rtl_basic_dma64 (
    input wire clk,
    input wire rst,

    input wire [31:0] conf_info_reg0,
    input wire [31:0] conf_info_reg1,
    input wire conf_done,

    output reg acc_done,
    output wire [31:0] debug,

    // DMA read control
    input wire dma_read_ctrl_ready,
    output reg dma_read_ctrl_valid,
    output reg [31:0] dma_read_ctrl_data_index,
    output reg [31:0] dma_read_ctrl_data_length,
    output reg [2:0] dma_read_ctrl_data_size,
    output reg [5:0] dma_read_ctrl_data_user,

    // DMA read channel
    output reg dma_read_chnl_ready,
    input wire dma_read_chnl_valid,
    input wire [63:0] dma_read_chnl_data,

    // DMA write control
    input wire dma_write_ctrl_ready,
    output reg dma_write_ctrl_valid,
    output reg [31:0] dma_write_ctrl_data_index,
    output reg [31:0] dma_write_ctrl_data_length,
    output reg [2:0] dma_write_ctrl_data_size,
    output reg [5:0] dma_write_ctrl_data_user,

    // DMA write channel
    input wire dma_write_chnl_ready,
    output reg dma_write_chnl_valid,
    output reg [63:0] dma_write_chnl_data
);

reg [63:0] fifo [0:15];
reg [3:0] rd_ptr, wr_ptr;
reg [4:0] count;
reg [2:0] state;

assign debug = {27'd0, state};

localparam IDLE      = 3'd0,
           DMA_READ  = 3'd1,
           WAIT_FIFO = 3'd2,
           DMA_WRITE = 3'd3,
           DONE      = 3'd4;

always @(posedge clk or negedge rst) begin
    if (!rst) begin
        state <= IDLE;
        dma_read_ctrl_valid <= 0;
        dma_write_ctrl_valid <= 0;
        dma_read_chnl_ready <= 0;
        dma_write_chnl_valid <= 0;
        acc_done <= 0;
        count <= 0;
        rd_ptr <= 0;
        wr_ptr <= 0;
    end else begin
        case (state)
            IDLE: begin
                acc_done <= 0;
                if (conf_done) begin
                    dma_read_ctrl_valid <= 1;
                    dma_read_ctrl_data_index <= 32'd0; // Puedes configurarlo por conf_info_reg
                    dma_read_ctrl_data_length <= 32'd16;
                    dma_read_ctrl_data_size <= 3'b011; // 64 bits
                    dma_read_ctrl_data_user <= 5'd0;
                    dma_read_chnl_ready <= 1;
                    count <= 0;
                    wr_ptr <= 0;
                    state <= DMA_READ;
                end
            end

            DMA_READ: begin
                if (dma_read_ctrl_valid && dma_read_ctrl_ready)
                    dma_read_ctrl_valid <= 0;

                if (dma_read_chnl_valid && dma_read_chnl_ready) begin
                    fifo[wr_ptr] <= dma_read_chnl_data + 100;
                    wr_ptr <= wr_ptr + 1;
                    count <= count + 1;
                    if (count == 15) begin
                        dma_read_chnl_ready <= 0;
                        state <= WAIT_FIFO;
                    end
                end
            end

            WAIT_FIFO: begin
                dma_write_ctrl_valid <= 1;
                dma_write_ctrl_data_index <= 32'd32; // Ejemplo desplazamiento
                dma_write_ctrl_data_length <= 32'd16;
                dma_write_ctrl_data_size <= 3'b011; // 64 bits
                dma_write_ctrl_data_user <= 5'd0;
                rd_ptr <= 0;
                count <= 0;
                state <= DMA_WRITE;
            end

            DMA_WRITE: begin
                if (dma_write_ctrl_valid && dma_write_ctrl_ready)
                    dma_write_ctrl_valid <= 0;

                dma_write_chnl_valid <= (count < 16);
                dma_write_chnl_data <= fifo[rd_ptr];

                if (dma_write_chnl_valid && dma_write_chnl_ready) begin
                    rd_ptr <= rd_ptr + 1;
                    count <= count + 1;
                    if (count == 15) begin
                        dma_write_chnl_valid <= 0;
                        state <= DONE;
                    end
                end
            end

            DONE: begin
                acc_done <= 1'b1;
                state <= IDLE;
            end
        endcase
    end
end

endmodule
