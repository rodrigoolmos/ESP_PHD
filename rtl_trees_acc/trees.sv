module forest_top #(
  parameter int N_TREES          = 16,
  parameter int N_NODE_AND_LEAFS = 256,
  parameter int N_FEATURE        = 32
)(
  input  logic                                    clk,
  input  logic                                    rst_n,
  input  logic                                    start,

  input  logic                                    load_trees,
  input  logic [$clog2(N_NODE_AND_LEAFS)-1:0]     n_node,
  input  logic [$clog2(N_TREES)-1:0]              n_tree,
  input  logic [63:0]                             tree_nodes,

  input  logic                                    load_features,
  input  logic [31:0]                             n_feature,
  input  logic [63:0]                             features2,

  output logic signed [31:0]                      prediction,
  output logic                                    done
);

  localparam int FEAT_IDX_W       = $clog2(N_FEATURE);
  localparam int CNT_W            = $clog2(N_TREES+1);

  // ---------------------------------------------------
  //  Feature and tree memory
  // ---------------------------------------------------
  logic [31:0]                      features   [N_FEATURE];
  logic [63:0]                      tree_mem   [N_TREES][N_NODE_AND_LEAFS];

  logic [31:0]                      leaf_vals  [N_TREES];
  logic [N_TREES-1:0]               tree_done;

  logic [FEAT_IDX_W-1:0]            feature_idx[N_TREES];
  logic [$clog2(N_NODE_AND_LEAFS)-1:0] 
                                    node_idx   [N_TREES];

  logic [CNT_W-1:0]                 voted_features [N_FEATURE];
  logic [FEAT_IDX_W-1:0]            value_prediction;
  logic                             prediction_done;

  // ---------------------------------------------------
  //  N_TREES engine instances
  // ---------------------------------------------------
  genvar t;
  generate
    for (t = 0; t < N_TREES; t++) begin : TREE_INST
      tree #(
        .N_NODE_AND_LEAFS(N_NODE_AND_LEAFS),
        .N_FEATURE(N_FEATURE)
      ) tree_u (
        .clk           (clk),
        .rst_n         (rst_n),
        .start         (start),
        .feature       (features[feature_idx[t]]),
        .feature_index(feature_idx[t]),
        .node          (tree_mem[t][node_idx[t]]),
        .node_index    (node_idx[t]),
        .leaf_value    (leaf_vals[t]),
        .done          (tree_done[t])
      );
    end
  endgenerate

  always_ff @(posedge clk) begin
    if (load_trees) begin
      tree_mem[n_tree][n_node] <= tree_nodes;
    end
  end

  always_ff @(posedge clk) begin
    if (load_features) begin
      features[n_feature] <= features2[31:0];
      features[n_feature+1] <= features2[63:32];
    end
  end

  // ---------------------------------------------------
  //  Votation FSM
  // ---------------------------------------------------
  typedef enum logic [1:0] { IDLE, COUNT, SELECT } vote_st_t;
  vote_st_t vote_st, vote_nxt;

  integer i;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      vote_st        <= IDLE;
      prediction_done<= 1'b0;
      for (i=0; i<N_FEATURE; i++) voted_features[i] <= '0;
    end else begin
      vote_st        <= vote_nxt;
      case (vote_st)
        IDLE: begin
          if (start && &tree_done) begin
            for (i=0; i<N_FEATURE; i++) voted_features[i] <= '0;
          end
        end
        COUNT: begin
          for (i=0; i<N_TREES; i++) begin
            voted_features[ leaf_vals[i] ] <= voted_features[ leaf_vals[i] ] + 1;
          end
        end
        SELECT: begin
          // Select the most voted feature
        end
      endcase

      // handshake done
      prediction_done<= (vote_st == SELECT);
    end
  end

  // ---------------------------------------------------
  //  Next‐state of the FSM
  // ---------------------------------------------------
  always_comb begin
    vote_nxt = vote_st;
    case (vote_st)
      IDLE:   if (start && &tree_done) vote_nxt = COUNT;
      COUNT:  vote_nxt = SELECT;
      SELECT: vote_nxt = IDLE;
    endcase
  end

  // ---------------------------------------------------
  //  Find the most voted feature
  // ---------------------------------------------------
  always_comb begin
    value_prediction = '0;
    for (i = 0; i < N_FEATURE; i++) begin
      if (voted_features[i] > voted_features[value_prediction])
        value_prediction = i[FEAT_IDX_W-1:0];
    end
  end

  // ---------------------------------------------------
  //  Store votation
  // ---------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      prediction <= '0;
      done       <= 1'b0;
    end else if (prediction_done) begin
      prediction <= value_prediction;
      done       <= 1'b1;
    end else if (start) begin
      done       <= 1'b0;
    end
  end

endmodule
