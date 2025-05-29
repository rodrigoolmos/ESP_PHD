module name #(
    parameter int N_NODE_AND_LEAFS = 256,
    parameter int N_FEATURE        = 32
) (
    input  logic                                    clk,
    input  logic                                    rst_n,
    input  logic                                    start,
    input  logic [31:0]                             feature,
    output logic [$clog2(N_FEATURE)-1:0]            feature_index,
    input  logic [63:0]                             node,
    output logic [$clog2(N_FEATURE)-1:0]            node_index,
    output logic signed [31:0]                      leaf_value,
    output logic                                    done
);

    typedef enum logic[1:0] { IDLE, FETCH, PROCESS, DONE} tree_state;
    tree_state tree_st;

    typedef struct packed {
        logic [7:0]   f_index;
        logic [7:0]   leaf_or_node;
        logic [15:0]  next_node_right_index;
        logic [31:0]  value;
    } tree_camps_t;

    tree_camps_t camps;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tree_st <= IDLE;
            feature_index <= 0;
            node_index <= 0;
            leaf_value <= 0;
            done <= 0;
        end else begin
            case (tree_st)
                IDLE: begin
                    if (start) begin
                        tree_st <= FETCH;
                        feature_index <= 0;
                        node_index <= 0;
                        leaf_value <= 0;
                        done <= 0;
                    end
                end

                FETCH: begin
                    // Fetch the next feature and node
                    tree_st <= PROCESS;
                    camps <= tree_camps_t'(node);
                end

                PROCESS: begin
                    // Process the current node
                    if (camps.leaf_or_node == 0) begin
                        // It's a leaf node, return the leaf value
                        leaf_value <= camps.value;
                        tree_st <= DONE;
                    end else begin
                        // It's a decision node, update feature index and node index
                        feature_index <= camps.f_index;
                        if (feature < camps.value) begin
                            node_index <= node_index +1;
                        end else begin
                            node_index <= camps.next_node_right_index;
                        end
                        // Prepare for next fetch
                        tree_st <= FETCH;
                    end

                end

                DONE: begin
                    done <= 1; // Indicate processing is done
                    tree_st <= IDLE; // Reset state for next operation
                end

                default: tree_st <= IDLE; // Fallback to IDLE state
            endcase
        end
    end


endmodule