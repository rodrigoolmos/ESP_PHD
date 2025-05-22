`timescale 1us/1ns

module rtl_trees #(
    parameter integer MAX_SAMPLES           = 10000,                 // Number max features samples
    parameter integer N_FEATURES_SAMPLE     = 32,                    // Number max features samples
    parameter integer N_TREES               = 128,                   // Number of trees in the forest
    parameter integer TREES_LEN             = 256                    // Tree length (number of nodes)
) (
    input  logic        clk,
    input  logic        rst_n,                          // Active-low reset

    // Configuration
    input  logic [31:0] load_trees,                     // FLAG: load trees
    input  logic [31:0] n_features,                     // Number of features
    input  logic [31:0] n_samples,                      // Number of samples
    input  logic        conf_done,                      // One-cycle pulse: config valid

    // Accelerator status
    output logic        acc_done,                       // One-cycle pulse: task done
    output logic [31:0] debug,                          // FSM state for debug

    // DMA read control
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

  localparam integer TREES_LEN_BITS  = $clog2(TREES_LEN);    // Number of bits to address a tree



  // State machine encoding
  typedef enum logic [2:0] {
    IDLE      = 0,
    DMA_READ  = 1,
    COMPUTE   = 2,
    DMA_WRITE = 3,
    DONE      = 4
  } state_e;

  state_e                         state;
  logic [63:0]                    trees[N_TREES-1:0][TREES_LEN-1:0];                      // Trees data
  logic [31:0]                    features[N_FEATURES_SAMPLE*MAX_SAMPLES-1:0];            // Features data
  logic [31:0]                    predictions[MAX_SAMPLES-1:0];                           // Predictions data
  logic [31:0]                    rd_ptr, wr_ptr;
  logic [TREES_LEN_BITS-1:0]      address_node;
  logic [31-TREES_LEN_BITS:0]     address_tree;
  logic                           end_compute;

  logic [63:0]                    cnt_test;

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
            if (load_trees[0])
              dma_read_ctrl_data_length <= N_TREES*TREES_LEN;
            else begin
              // 2 beats of 64 bits means 2 features per CLK
              dma_read_ctrl_data_length <= n_samples*n_features/2; 
            end
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

            // Load trees data
            if (load_trees[0]) begin
              trees[address_tree][address_node] <= dma_read_chnl_data;
              rd_ptr       <= rd_ptr + 1;

              if (rd_ptr == dma_read_ctrl_data_length-1) begin
                dma_read_chnl_ready <= 0;
                rd_ptr              <= 0;
                state               <= COMPUTE;
              end
            // Load features data
            end else begin
              features[rd_ptr+0] <= dma_read_chnl_data[31:0];
              features[rd_ptr+1] <= dma_read_chnl_data[63:32];
              rd_ptr       <= rd_ptr + 2;

              if (rd_ptr == n_samples*n_features-2) begin
                dma_read_chnl_ready <= 0;
                rd_ptr              <= 0;
                state               <= COMPUTE;
              end
            end
            

          end
        end

        COMPUTE: begin
          if (load_trees[0]) begin
            dma_write_ctrl_valid       <= 1;
            dma_write_ctrl_data_index  <= 0;
            dma_write_ctrl_data_length <= 1;
            dma_write_ctrl_data_size   <= 3'b011;
            dma_write_ctrl_data_user   <= 0;
            state                      <= DMA_WRITE;
          end else begin
            if (end_compute == 1) begin
              dma_write_ctrl_valid       <= 1;
              dma_write_ctrl_data_index  <= 0;
              dma_write_ctrl_data_length <= n_samples;
              dma_write_ctrl_data_size   <= 3'b011;
              dma_write_ctrl_data_user   <= 0;
              state                      <= DMA_WRITE;
            end
          end
          if (dma_write_ctrl_valid && dma_write_ctrl_ready)
            dma_write_ctrl_valid <= 0;
        end

        DMA_WRITE: begin
          if (dma_write_ctrl_valid && dma_write_ctrl_ready)
            dma_write_ctrl_valid <= 0;

          dma_write_chnl_valid <= (wr_ptr < dma_write_ctrl_data_length);

          if (dma_write_chnl_valid && dma_write_chnl_ready) begin
            wr_ptr <= wr_ptr + 1;
            if (wr_ptr == dma_write_ctrl_data_length-1) begin
              dma_write_chnl_valid <= 0;
              wr_ptr               <= 0;
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
      end_compute <= 0;
      cnt_test   <= 0;
    end else begin
      if (state == COMPUTE) begin
        if (cnt_test < MAX_SAMPLES) begin
          cnt_test <= cnt_test + 1;
          predictions[cnt_test] <= cnt_test;
        end else begin
          end_compute <= 1;
        end
      end else begin
        cnt_test   <= 0;
        end_compute <= 0;
      end
    end
  end

  always_comb begin
    if (load_trees[0]) begin
      dma_write_chnl_data  = 32'hDEAD_BEEF; // Dummy data
    end else begin
      dma_write_chnl_data  = 32'h0BAD_C0DE; // Dummy data
    end
  end

  always_comb begin
    address_node = rd_ptr[TREES_LEN_BITS-1:0];
    address_tree = rd_ptr[31:TREES_LEN_BITS];
  end


endmodule
