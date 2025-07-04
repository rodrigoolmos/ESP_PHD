module trees #(
	parameter int N_TREES          = 16,
	parameter int N_NODE_AND_LEAFS = 256,
	parameter int N_FEATURE        = 32,
	parameter int N_CLASES         = 32
)(
	input  logic                          		clk,
	input  logic                          		rst_n,
	input  logic                          		start,

	// Port para carga de nodos
	input  logic                          		load_trees,
	input  logic [$clog2(N_NODE_AND_LEAFS)-1:0] n_node,
	input  logic [$clog2(N_TREES)-1:0]         	n_tree,
	input  logic [63:0]                   		tree_nodes,

	// Características de entrada
	input  logic [N_FEATURE-1:0][31:0]    		features,

	// Salida final
	output logic [7:0]                    		prediction,
	output logic                          		done,
	output logic                          		idle_sys
);

	// ----------------------------------------------------------------
	//  Anchos internos
	// ----------------------------------------------------------------
	localparam int FEAT_IDX_W = $clog2(N_FEATURE);
	localparam int N_CLASES_W = $clog2(N_CLASES);
	localparam int CNT_W      = $clog2(N_TREES+1);
	localparam int N_NODE_W   = $clog2(N_NODE_AND_LEAFS);

	// ----------------------------------------------------------------
	//  Señales para el ensamble de árboles
	// ----------------------------------------------------------------
	logic [31:0]               leaf_vals   [0:N_TREES-1];
	logic [N_TREES-1:0]        tree_done;
	logic [FEAT_IDX_W-1:0]     feature_idx [0:N_TREES-1];
	logic [N_NODE_W-1:0]       node_idx    [0:N_TREES-1];

	// ----------------------------------------------------------------
	//  Contadores para votación
	// ----------------------------------------------------------------
	logic [CNT_W-1:0]          voted_trees  [0:N_CLASES-1];
	logic [CNT_W-1:0]          tmp_voted;
	logic [7:0]                value_pred;
	logic [CNT_W-1:0]          cnt_trees;
	logic [N_CLASES_W-1:0]     cnt_vote;

	// FSM de control de votación
	typedef enum logic [1:0] { VS_IDLE, VS_COUNT, VS_VOTE, VS_SELECT } vote_st_t;
	vote_st_t vote_st;
	logic     start_ff;

	// ----------------------------------------------------------------
	//  Instanciación de N_TREES BRAMs y motores tree
	// ----------------------------------------------------------------
	genvar t;
	generate
		for (t = 0; t < N_TREES; t++) begin : GEN_TREES
			// Cada árbol tiene su BRAM individual inferida
			(* ram_style = "block" *)
			logic [63:0] tree_mem_t [0:N_NODE_AND_LEAFS-1];

			// Dato leído registrado
			logic [63:0] tree_node_q;

			// Escritura y lectura síncronas en un solo always_ff
			always_ff @(posedge clk) begin
				// Escritura de nodos
				if (load_trees && (n_tree == t))
				  	tree_mem_t[n_node] <= tree_nodes;
			end
		    
		  	always_comb tree_node_q <= tree_mem_t[ node_idx[t] ];
		  
		    
			// Instancia del árbol de decisión
			tree #(
				.N_NODE_AND_LEAFS(N_NODE_AND_LEAFS),
				.N_FEATURE       (N_FEATURE)
			) tree_u (
				.clk           (clk),
				.rst_n         (rst_n),
				.start         (start),
				.feature       (features[ feature_idx[t] ]),
				.feature_index (feature_idx[t]),
				.node          (tree_node_q),
				.node_index    (node_idx[t]),
				.leaf_value    (leaf_vals[t]),
				.done          (tree_done[t])
			);
		end
	endgenerate

	// ----------------------------------------------------------------
	//  FSM de salida: combinar done y generar prediction
	// ----------------------------------------------------------------
	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			for (int i = 0; i < N_CLASES; i++)
				voted_trees[i] <= 0;
			value_pred   <= 0;      
			tmp_voted    <= 0;
			cnt_trees    <= 0;
			cnt_vote     <= 0;
			start_ff     <= 0;
			vote_st      <= VS_IDLE;
			done         <= 0;
			idle_sys	 <= 1;
		end else begin
			case (vote_st)
			VS_IDLE: begin
				done         <= 0;
				cnt_trees    <= 0;
				idle_sys	 <= 1;
				for (int i = 0; i < N_CLASES; i++)
					voted_trees[i] <=0;
				if (start)
					start_ff   <= 1;
				if (start_ff && &tree_done) begin
					idle_sys	 <= 0;
					vote_st    <= VS_COUNT;
				end
			end

			VS_COUNT: begin
				voted_trees[leaf_vals[cnt_trees]] <= voted_trees[leaf_vals[cnt_trees]] + 1;
				cnt_trees    <= cnt_trees + 1;
				if (cnt_trees == N_TREES-1) begin
					vote_st    <= VS_VOTE;
					tmp_voted   <= 0;
					cnt_vote    <= 0;
				end
			end

			VS_VOTE: begin
				cnt_vote <= cnt_vote + 1;
				if (voted_trees[cnt_vote] > tmp_voted) begin
					tmp_voted   <= voted_trees[cnt_vote];
					value_pred  <= cnt_vote;
				end
				if (cnt_vote == N_CLASES-1) begin
					vote_st    <= VS_SELECT;
				end
			end

			VS_SELECT: begin
				start_ff     <= 0;
				prediction   <= value_pred;
				done         <= 1;
				vote_st      <= VS_IDLE;
			end
			endcase
		end
	end

endmodule
