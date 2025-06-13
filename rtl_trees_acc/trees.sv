module trees #(
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
  localparam int N_NODE_W         = $clog2(N_NODE_AND_LEAFS);

  // ---------------------------------------------------
  //  Feature and tree memory
  // ---------------------------------------------------
  logic [31:0]                      features   [N_FEATURE-1:0];
  logic [63:0]                      tree_mem   [N_TREES-1:0][N_NODE_AND_LEAFS-1:0];

  logic [31:0]                      leaf_vals  [N_TREES-1:0];
  logic [N_TREES-1:0]               tree_done;

  logic [FEAT_IDX_W-1:0]            feature_idx [N_TREES-1:0];
  logic [N_NODE_W-1:0]              node_idx [N_TREES-1:0];

  logic [CNT_W-1:0]                 voted_features [N_FEATURE-1:0];
  logic [CNT_W-1:0]                 tmp_voted;
  logic [CNT_W-1:0]                 voted_features_ff [N_FEATURE-1:0];
  logic [FEAT_IDX_W-1:0]            value_prediction;
  logic                             start_ff;

  // ---------------------------------------------------
  //  N_TREES engine instances
  // ---------------------------------------------------
  genvar t;
  generate
    for (t = 0; t < N_TREES; t++) begin
      tree #(
        .N_NODE_AND_LEAFS(N_NODE_AND_LEAFS),
        .N_FEATURE(N_FEATURE)
      ) tree_u (
        .clk           (clk),
        .rst_n         (rst_n),
        .start         (start),
        .feature       (features[feature_idx[t]]),
        .feature_index (feature_idx[t]),
        .node          (tree_mem[t][node_idx[t]]),
        .node_index    (node_idx[t]),
        .leaf_value    (leaf_vals[t]),
        .done          (tree_done[t])
      );
    end
  endgenerate

  typedef enum logic [1:0] { IDLE, COUNT, SELECT } vote_st_t;
  vote_st_t vote_st;

  // ---------------------------------------------------
  //  LOAD TREES AND FEATURES
  // ---------------------------------------------------
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
  //  VOTE PROCESS
  // ---------------------------------------------------
  always_comb begin
    for (int i = 0; i < N_FEATURE; i = i + 1) begin
        voted_features[i] = 0;
    end
    for (int i = 0; i < N_TREES; i = i + 1) begin
        voted_features[ leaf_vals[i] ]++;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
        for (int i = 0; i < N_FEATURE; i = i + 1) begin
            voted_features_ff[i] <= 0;
        end
      end else begin
        for (int i = 0; i < N_FEATURE; i = i + 1) begin
            voted_features_ff[i] <= voted_features[i];
        end
      end    
  end

  always_comb begin
      tmp_voted        = voted_features_ff[0];
      value_prediction = 0;
      for (int i = 1; i < N_FEATURE; i = i + 1) begin
          if (voted_features_ff[i] > tmp_voted) begin
              tmp_voted        = voted_features_ff[i];
              value_prediction = i;
          end
      end
  end


  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      prediction <= 0;
      done <= 0;
      vote_st <= IDLE;
    end else begin
      case (vote_st)

        IDLE: begin
          if (start) begin
            start_ff <= 1;
          end
          done <= 0;
          if (start_ff && &tree_done) begin
            vote_st <= COUNT;
          end
        end

        COUNT: begin
            vote_st <= SELECT;
        end

        SELECT: begin
          start_ff <= 0;
          prediction <= value_prediction;
          done <= 1;
          vote_st <= IDLE;
        end

      endcase
    end
  end


endmodule
