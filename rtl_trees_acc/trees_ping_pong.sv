module trees_ping_pong #(
	parameter N_TREES          					= 16,
	parameter N_NODE_AND_LEAFS 					= 256,
	parameter N_FEATURE        					= 32,
	parameter MAX_BURST        					= 5000
)(
    input  logic                                    	clk,
    input  logic                                    	rst_n,
    input  logic                                    	start,

    input  logic                                    	load_trees,
    input  logic [$clog2(N_NODE_AND_LEAFS)-1:0]     	n_node,
    input  logic [$clog2(N_TREES)-1:0]              	n_tree,
    input  logic [63:0]                             	tree_nodes,

    input  logic                                   		load_features,
    input  logic [$clog2(MAX_BURST*N_FEATURE/2)-1:0]	feature_addr,
    input  logic [$clog2(MAX_BURST):0]     				burst_len,
    input  logic [63:0]                             	features2,

    output logic [63:0]									prediction,
    input  logic [$clog2(MAX_BURST):0]					prediction_addr,
    output logic										done
);

	localparam HALF_N_FEATURE     = N_FEATURE/2;
	localparam MAX_BURST_BITS     = $clog2(MAX_BURST);

    typedef enum logic[1:0] { P_IDLE, P_PING, P_PONG, P_WAIT} process_state;
	process_state proc_st;

    typedef enum logic[1:0] { C_IDLE, C_PING, C_PONG, C_WAIT} copy_state;
	copy_state copy_st;

	logic [63:0] 					prediction_mem [(MAX_BURST-1)/8:0];
    logic [7:0]                    	prediction_set;
    logic [7:0][7:0]                prediction_packed;
	logic [MAX_BURST_BITS:0] 		prediction_index;



	logic [63:0] 						features_mem [MAX_BURST*HALF_N_FEATURE-1:0];
	logic [N_FEATURE-1:0][31:0] 		features_mux;
	logic [HALF_N_FEATURE-1:0][63:0] 	features_ping;
	logic [HALF_N_FEATURE-1:0][63:0] 	features_pong;
	logic [$clog2(N_FEATURE)-1:0] 		feature_index;
	logic [31:0] 						burst_index;

	logic 								c_ping_ready;
	logic 								c_pong_ready;
	logic 								c_ping_pong;

	logic 								p_ping_ready;
	logic 								p_pong_ready;
	logic 								p_ping_pong;

	logic 								start_set;
	logic 								done_set;

	logic								load_predictions;

    trees #(
        .N_TREES(N_TREES),
        .N_NODE_AND_LEAFS(N_NODE_AND_LEAFS),
        .N_FEATURE(N_FEATURE)
	)trees_u (
        .clk(clk),
        .rst_n(rst_n),
        .start(start_set),

        .load_trees(load_trees),
        .n_node(n_node),
        .n_tree(n_tree),
        .tree_nodes(tree_nodes),

        .features(features_mux),

        .prediction(prediction_set),
        .done(done_set)
    );

	// ---------------------------------------------------
	//  LOAD FEATURES
	// ---------------------------------------------------
	always_ff @(posedge clk or negedge rst_n)
    	if (load_features)
    	  	features_mem[feature_addr] <= features2;

	// ---------------------------------------------------
	//  LOAD PREDICTIONS
	// ---------------------------------------------------
	always_ff @(posedge clk or negedge rst_n)
    	if (load_predictions)
			prediction_mem[((prediction_index - 1) >> 3)] <= prediction_packed;

	// ---------------------------------------------------
	//  READ PREDICTIONS
	// ---------------------------------------------------
	always_comb
		prediction = prediction_mem[prediction_addr];

	// ---------------------------------------------------
	//  COPY FEATURES PING PONG
	// ---------------------------------------------------
	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			copy_st <= C_IDLE;
			p_ping_ready <= 0;
			p_pong_ready <= 0;
			c_ping_pong <= 1;
			feature_index <= 0;
			burst_index <= 0;
			features_ping <= 0;
			features_pong <= 0;
		end else begin
			case (copy_st)
				C_IDLE: begin
					if (start) begin
						copy_st <= C_WAIT;
						p_ping_ready <= 0;
						p_pong_ready <= 0;
						burst_index <= 0;
						feature_index <= 0;
						c_ping_pong <= 1;
					end
				end
				C_WAIT: begin
					feature_index <= 0;
					if (c_ping_ready && c_ping_pong)
						copy_st <= C_PING;
					if (c_pong_ready && !c_ping_pong)
						copy_st <= C_PONG;
					if (burst_index == burst_len) begin
						copy_st <= C_IDLE;
					end
				end
				C_PING: begin
					if (feature_index < HALF_N_FEATURE) begin
						features_ping[feature_index] <= 
							features_mem[feature_index + {burst_index, {$clog2(HALF_N_FEATURE){1'b0}}}];
						feature_index <= feature_index + 1;
						p_ping_ready <= 0;
					end else begin
						burst_index <= burst_index + 1;
						p_ping_ready <= 1;
						c_ping_pong <= 0;
						copy_st <= C_WAIT;
					end
				end
				C_PONG: begin
					if (feature_index < HALF_N_FEATURE) begin
						features_pong[feature_index] <= 
							features_mem[feature_index + {burst_index, {$clog2(HALF_N_FEATURE){1'b0}}}];
						feature_index <= feature_index + 1;
						p_pong_ready <= 0;
					end else begin
						burst_index <= burst_index + 1;
						p_pong_ready <= 1;
						c_ping_pong <= 1;
						copy_st <= C_WAIT;
					end
				end
			endcase
		end
	end

	// ---------------------------------------------------
	//  PROCESS FEATURES PING PONG
	// ---------------------------------------------------
	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			proc_st <= P_IDLE;
			c_ping_ready <= 1;
			c_pong_ready <= 1;
			p_ping_pong <= 1;
			prediction_packed <= 0;
			start_set <= 0;
			load_predictions <= 0;
			prediction_index <= 0;
		end else begin
			case (proc_st)
				P_IDLE: begin
					start_set <= 0;
					done <= 0;
					prediction_packed <= 0;
					if (start) begin
						proc_st <= P_WAIT;
						c_ping_ready <= 1;
						c_pong_ready <= 1;
						p_ping_pong <= 1;
						prediction_index <= 0;
					end
				end
				P_WAIT: begin
					load_predictions <= 0;
					if (p_ping_ready && p_ping_pong) begin
						proc_st <= P_PING;
						start_set <= 1;
						c_ping_ready <= 0;
						/* 
						Each 64-bit word in features_ping contains two 32-bit features;
						the assignment to features_mux splits them to feed the tree ensemble.
						*/
						features_mux <= features_ping;
					end
					if (p_pong_ready && !p_ping_pong) begin
						proc_st <= P_PONG;
						start_set <= 1;
						c_pong_ready <= 0;
						/* 
						Each 64-bit word in features_ping contains two 32-bit features;
						the assignment to features_mux splits them to feed the tree ensemble.
						*/
						features_mux <= features_pong;
					end
					if (prediction_index == burst_len) begin
						proc_st <= P_IDLE;
						done <= 1;
					end
				end
				P_PING: begin
					start_set <= 0;
					if (done_set) begin
						load_predictions <= 1;
						prediction_packed[prediction_index[2:0]] <= prediction_set[7:0];
						prediction_index <= prediction_index + 1;
						proc_st <= P_WAIT;
						c_ping_ready <= 1;
						p_ping_pong <= 0;
					end
				end
				P_PONG: begin
					start_set <= 0;
					if (done_set) begin
						load_predictions <= 1;
						prediction_packed[prediction_index[2:0]] <= prediction_set[7:0];
						prediction_index <= prediction_index + 1;
						proc_st <= P_WAIT;
						c_pong_ready <= 1;
						p_ping_pong <= 1;
					end
				end
			endcase
		end
	end

endmodule