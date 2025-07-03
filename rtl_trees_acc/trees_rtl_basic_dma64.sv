module trees_rtl_basic_dma64 #(
	parameter N_TREES          					= 128,
	parameter N_NODE_AND_LEAFS 					= 256,		// POWER OF 2
	parameter N_FEATURE        					= 32,
	parameter MAX_BURST        					= 5000
) (
	input  logic        clk,
	input  logic        rst,                          // Active-low reset

	// Configuration
	input  logic [31:0] conf_info_load_trees,
	input  logic [31:0] conf_info_burst_len,
	input  logic        conf_done,

	// Accelerator status
	output logic        acc_done,

	// DMA read control
	input  logic        dma_read_ctrl_ready,
	output logic        dma_read_ctrl_valid,
	output logic [31:0] dma_read_ctrl_data_index,
	output logic [31:0] dma_read_ctrl_data_length,
	output logic [2:0]  dma_read_ctrl_data_size,
	output logic [5:0]  dma_read_ctrl_data_user,

	// DMA read channel
	output logic        dma_read_chnl_ready,
	input  logic        dma_read_chnl_valid,
	input  logic [63:0] dma_read_chnl_data,

	// DMA write control
	input  logic        dma_write_ctrl_ready,
	output logic        dma_write_ctrl_valid,
	output logic [31:0] dma_write_ctrl_data_index,
	output logic [31:0] dma_write_ctrl_data_length,
	output logic [2:0]  dma_write_ctrl_data_size,
	output logic [5:0]  dma_write_ctrl_data_user,

	// DMA write channel
	input  logic        dma_write_chnl_ready,
	output logic        dma_write_chnl_valid,
	output logic [63:0] dma_write_chnl_data
);

	localparam integer TREES_LEN_BITS  = $clog2(N_NODE_AND_LEAFS);

	typedef enum logic [2:0] {
		IDLE      = 0,
		DMA_READ  = 1,
		COMPUTE   = 2,
		DMA_WRITE = 3,
		DONE      = 4
	} state_e;

	state_e                         state;
	logic [31:0]                    rd_ptr, wr_ptr;
	logic [TREES_LEN_BITS-1:0]      address_node;
	logic [31-TREES_LEN_BITS:0]     address_tree;
	logic                           end_compute;
	logic                           load_features;
	logic [63:0]                    prediction;
	logic                           start;
	logic                           writing;

	logic                           load_trees_s;

	// TREES COMPUTE UNIT
	trees_ping_pong #(
		.N_TREES(N_TREES),
		.N_NODE_AND_LEAFS(N_NODE_AND_LEAFS),
		.N_FEATURE(N_FEATURE),
		.MAX_BURST(MAX_BURST)
	) trees_ping_pong_ins (
		.clk(clk),
		.rst_n(rst),
		.start(start),
		
		.load_trees(load_trees_s),
		.n_node(address_node),
		.n_tree(address_tree),
		.tree_nodes(dma_read_chnl_data),

		.load_features(load_features),
		.feature_addr(rd_ptr),
		.burst_len(conf_info_burst_len),
		.features2(dma_read_chnl_data),

		.prediction(prediction),
		.prediction_addr(wr_ptr),
		.done(end_compute)
	);

	always_ff @(posedge clk or negedge rst) begin
		if (!rst) begin
			state                   	<= IDLE;
			dma_read_ctrl_valid     	<= 0;
			dma_read_ctrl_data_index 	<= 0;
			dma_read_ctrl_data_length 	<= 0;
			dma_read_ctrl_data_size 	<= 0;
			dma_read_ctrl_data_user 	<= 0;

			dma_write_ctrl_valid    	<= 0;
			dma_write_ctrl_data_index 	<= 0;
			dma_write_ctrl_data_length 	<= 0;
			dma_write_ctrl_data_size 	<= 0;
			dma_write_ctrl_data_user 	<= 0;

			dma_read_chnl_ready     	<= 0;
			writing                 	<= 0;
			acc_done                	<= 0;
			rd_ptr                  	<= 0;
			wr_ptr                  	<= 0;
			start                   	<= 0;
			load_features           	<= 0;
		end else begin
			case (state)
				IDLE: begin
					acc_done <= 0;
					if (conf_done) begin
						dma_read_ctrl_valid       <= 1;
						dma_read_ctrl_data_index  <= 0;
						if (conf_info_load_trees[0])
							dma_read_ctrl_data_length <= N_TREES * N_NODE_AND_LEAFS;
						else begin
							dma_read_ctrl_data_length <= (conf_info_burst_len * N_FEATURE + 1) >> 1; // FEATURES COME IN PAIRS
						end
						dma_read_ctrl_data_size   <= 3'b011;
						dma_read_ctrl_data_user   <= 0;
						dma_read_chnl_ready       <= 1;
						state                     <= DMA_READ;
					end
				end
				// DMA_READ state handles reading features or trees
				// If conf_info_load_trees[0] is set, it reads trees; otherwise,
				// it reads features.
				DMA_READ: begin
					start <= 0;
					if (dma_read_ctrl_valid && dma_read_ctrl_ready)
						dma_read_ctrl_valid <= 0;
					if(!conf_info_load_trees[0]) 
						load_features <= 1;

					if (dma_read_chnl_valid && dma_read_chnl_ready) begin
						rd_ptr <= rd_ptr + 1;
						if (rd_ptr == dma_read_ctrl_data_length - 1) begin
							start <= !conf_info_load_trees[0]; 						// Start computation only if not loading trees
							dma_read_chnl_ready <= 0;
							rd_ptr <= 0;
							state  <= COMPUTE;
							load_features		   	  <= 0;
						end
					end
				end
				
				COMPUTE: begin
					start <= 0;
					if (conf_info_load_trees[0]) begin
						dma_write_ctrl_valid       <= 1;
						dma_write_ctrl_data_index  <= 0;
						dma_write_ctrl_data_length <= 1;
						dma_write_ctrl_data_size   <= 3'b011;
						dma_write_ctrl_data_user   <= 0;
						state                      <= DMA_WRITE;
					end else if (end_compute) begin
						dma_write_ctrl_valid       <= 1;
						dma_write_ctrl_data_index  <= 0;
						dma_write_ctrl_data_length <= (conf_info_burst_len + 7) >> 3; //ceil(x / 8)
						dma_write_ctrl_data_size   <= 3'b011;
						dma_write_ctrl_data_user   <= 0;
						state                      <= DMA_WRITE;
					end

					if (dma_write_ctrl_valid && dma_write_ctrl_ready)
						dma_write_ctrl_valid <= 0;
				end

				DMA_WRITE: begin
					if (dma_write_ctrl_valid && dma_write_ctrl_ready)
						dma_write_ctrl_valid <= 0;

					if (wr_ptr < dma_write_ctrl_data_length)
						writing <= 1;
					else
						writing <= 0;

					if (writing && dma_write_chnl_ready) begin
						wr_ptr <= wr_ptr + 1;
						if (wr_ptr == dma_write_ctrl_data_length - 1) begin
							writing <= 0;
							wr_ptr  <= 0;
							state   <= DONE;
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

	always_comb dma_write_chnl_valid = writing;
	always_comb load_trees_s = state == DMA_READ ? conf_info_load_trees[0] : 0;

	always_comb begin
		if (state == DMA_WRITE) begin
			if (conf_info_load_trees[0])
				dma_write_chnl_data = 64'hDEAD_BEEF;
			else
				dma_write_chnl_data = prediction;
		end else begin
			dma_write_chnl_data = 64'd0;
		end
	end

	always_comb begin
		address_node = rd_ptr[TREES_LEN_BITS-1:0];
		address_tree = rd_ptr[31:TREES_LEN_BITS];
	end

endmodule
