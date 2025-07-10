`timescale 1us/1ns

module test_rtl_basic_dma64 (
    input  logic        clk,
    input  logic        rst_n,                         // Active-low reset

    // Configuration
    input  logic [31:0] conf_info_reg0,                 // Read data index
    input  logic [31:0] conf_info_reg1,                 // Read data length
    input  logic        conf_done,                      // One-cycle pulse: config valid

    // Accelerator status
    output logic        acc_done,                       // One-cycle pulse: task done
    output logic [31:0] debug,                          // FSM state for debug

    // DMA read control
    // If valid ready handshake is done you need to read dma_read_ctrl_data_length
    // if not bus gets stuck for that you need dma_read_chnl_ready dma_read_chnl_valid
    // handshake for dma_read_ctrl_data_length CLK clicles and dma_read_ctrl_data_length has to be
    // greater than 0
    input  logic        dma_read_ctrl_ready,            // Ready for new read request
    output logic        dma_read_ctrl_valid,            // Start a read
    output logic [31:0] dma_read_ctrl_data_index,       // Read offset (beats)
    output logic [31:0] dma_read_ctrl_data_length,      // Number of beats
    output logic [2:0]  dma_read_ctrl_data_size,        // Beat size (e.g. 011=64-bit)
    output logic [5:0]  dma_read_ctrl_data_user,        // USER field (mode)

    // DMA read channel
    output logic        dma_read_chnl_ready,            // Ready to receive data
    input  logic        dma_read_chnl_valid,            // Data valid
    input  logic [63:0] dma_read_chnl_data,             // Incoming beat

    // DMA write control
    // If valid ready handshake is done you need to read dma_write_ctrl_data_length
    // if not bus gets stuck for that you need dma_write_chnl_ready dma_write_chnl_valid
    // handshake for dma_write_ctrl_data_length CLK clicles and dma_write_ctrl_data_length has to be
    // greater than 0
    input  logic        dma_write_ctrl_ready,           // Ready for new write request
    output logic        dma_write_ctrl_valid,           // Start a write
    output logic [31:0] dma_write_ctrl_data_index,      // Write offset (beats)
    output logic [31:0] dma_write_ctrl_data_length,     // Number of beats
    output logic [2:0]  dma_write_ctrl_data_size,       // Beat size
    output logic [5:0]  dma_write_ctrl_data_user,       // USER field (consumers)

    // DMA write channel
    input  logic        dma_write_chnl_ready,           // Ready for write data
    output logic        dma_write_chnl_valid,           // Write data valid
    output logic [63:0] dma_write_chnl_data             // Outgoing beat
);

  localparam integer READ_LEN   = 32;                   // Number of beats to read
  localparam integer WRITE_LEN  = 16;                   // Number of beats to write
  localparam int UNROLL         = 16;                    // Unrolling factor
  localparam int N_CHUNKS       = READ_LEN / UNROLL;    // Number of chunks to compute


  // State machine encoding
  typedef enum logic [2:0] {
    IDLE      = 0,
    DMA_READ  = 1,
    COMPUTE   = 2,
    DMA_WRITE = 3,
    DONE      = 4
  } state_e;

  state_e           state;
  logic [63:0]      vec_a     [0:15];
  logic [63:0]      vec_b     [0:15];
  logic [63:0]      vec_c     [0:15];
  logic [31:0]      rd_ptr, wr_ptr;
  logic             end_compute;
  // índice interno
  logic [$clog2(N_CHUNKS):0] chunk_idx;

  // Expose state in upper bits of debug
  assign debug = {29'd0, state};

  // Sequential FSM
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state                   <= IDLE;
      dma_read_ctrl_valid     <= 0;
      dma_write_ctrl_valid    <= 0;
      dma_read_chnl_ready     <= 0;
      dma_write_chnl_valid    <= 0;
      acc_done                <= 0;
      rd_ptr                  <= 0;
      wr_ptr                  <= 0;
    end else begin
      case (state)
        IDLE: begin
          acc_done <= 0;
          if (conf_done) begin
            dma_read_ctrl_valid       <= 1;
            dma_read_ctrl_data_index  <= 0;
            dma_read_ctrl_data_length <= READ_LEN;
            dma_read_ctrl_data_size   <= 3'b011;
            dma_read_ctrl_data_user   <= 0;
            dma_read_chnl_ready       <= 1;
            state                     <= DMA_READ;
          end
        end

        DMA_READ: begin
          if (dma_read_ctrl_valid && dma_read_ctrl_ready)
            dma_read_ctrl_valid <= 0;

          if (dma_read_chnl_valid && dma_read_chnl_ready) begin

            // First half of the data
            if (wr_ptr < READ_LEN / 2)
              vec_a[wr_ptr] <= dma_read_chnl_data;
            // Second half of the data
            else
              vec_b[wr_ptr - READ_LEN / 2] <= dma_read_chnl_data;

            wr_ptr       <= wr_ptr + 1;
            if (wr_ptr == dma_read_ctrl_data_length-1) begin
              dma_read_chnl_ready <= 0;
              wr_ptr              <= 0;
              state               <= COMPUTE;
            end
          end
        end

        COMPUTE: begin
          if (end_compute == 1) begin
            dma_write_ctrl_valid       <= 1;
            dma_write_ctrl_data_index  <= 0;
            dma_write_ctrl_data_length <= WRITE_LEN;
            dma_write_ctrl_data_size   <= 3'b011;
            dma_write_ctrl_data_user   <= 0;
            state                      <= DMA_WRITE;
          end
        end

        DMA_WRITE: begin
          if (dma_write_ctrl_valid && dma_write_ctrl_ready)
            dma_write_ctrl_valid <= 0;

          dma_write_chnl_valid <= (rd_ptr < dma_write_ctrl_data_length);

          if (dma_write_chnl_valid && dma_write_chnl_ready) begin
            rd_ptr <= rd_ptr + 1;
            if (rd_ptr == dma_write_ctrl_data_length-1) begin
              dma_write_chnl_valid <= 0;
              rd_ptr               <= 0;
              state                <= DONE;
            end
          end
        end

        DONE: begin
          acc_done <= 1;
          state    <= IDLE;
        end
      endcase
    end
  end

  // Compute the result use example "SUMA DE DOS VECTORES LOOP UNROLLING (UNROLL)"
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      chunk_idx   <= 0;
      end_compute <= 0;
    end else begin
      if (state == COMPUTE) begin
        if (chunk_idx < N_CHUNKS) begin
          for (int u = 0; u < UNROLL; u++) begin
            vec_c[chunk_idx*UNROLL + u] <= 
              vec_a[chunk_idx*UNROLL + u] + vec_b[chunk_idx*UNROLL + u];
          end
          chunk_idx   <= chunk_idx + 1;
          end_compute <= 0;
        end else begin
          end_compute <= 1;
          chunk_idx   <= 0;
        end
      end else begin
        end_compute <= 0;
        chunk_idx   <= 0;
      end
    end
  end

  always_comb dma_write_chnl_data  = vec_c[rd_ptr];


endmodule
