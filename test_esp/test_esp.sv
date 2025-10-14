module test_esp;

    parameter t_clk = 10;

    logic clk;
    logic rst;

    /////////////////////////
    /* ESP signal declaration */

    logic acc_done;

	// DMA read control
    logic        dma_read_ctrl_valid;
	logic        dma_read_ctrl_ready;
    logic [31:0] dma_read_ctrl_data_length;
    logic [31:0] dma_read_ctrl_data_index;
    logic [31:0] dma_read_ctrl_data_size;
    logic [31:0] dma_read_ctrl_data_user;

	// DMA read channel
	logic        dma_read_chnl_ready;
	logic        dma_read_chnl_valid;
	logic [63:0] dma_read_chnl_data;

	// DMA write control
	logic        dma_write_ctrl_ready;
	logic        dma_write_ctrl_valid;
	logic [31:0] dma_write_ctrl_data_index;
	logic [31:0] dma_write_ctrl_data_length;
	logic [2:0]  dma_write_ctrl_data_size;
	logic [5:0]  dma_write_ctrl_data_user;

	// DMA write channel
	logic        dma_write_chnl_ready;
	logic        dma_write_chnl_valid;
	logic [63:0] dma_write_chnl_data;

    ////////////////////////
    /* assertions section */
    ////////////////////////

    property b_changes_only_on_a_rise(logic sigA, logic [31:0] sigB);
        @(posedge clk) disable iff (!rst)
            $changed(sigB) |-> $changed(sigA) || !sigA;
    endproperty

    // CHECK acc_done pulse
    assert property (@(posedge clk)
        disable iff (!rst)
        $rose(acc_done) |-> ##1 !acc_done
    ) else $error("acc_done pulse should be one cycle only");

    ////////   WRITE CONTROL ASSERTIONS   ////////
    // CHECK dma_write_ctrl_valid read_ctrl_ready handshake
    assert property (@(posedge clk)
        disable iff (!rst)
        dma_write_ctrl_valid && dma_write_ctrl_ready |-> ##1 !dma_write_ctrl_valid
    ) else $error("dma_write_ctrl_valid should be low one cycle after dma_write_ctrl_valid && dma_write_ctrl_ready");
    // CHECK dma_write_ctrl_data_length stability
    assert property (b_changes_only_on_a_rise(dma_write_ctrl_valid, dma_write_ctrl_data_length)) 
        else $error("dma_write_ctrl_data_length shouldn't change when dma_write_ctrl_valid is high");
    // CHECK dma_write_ctrl_data_index stability
    assert property (b_changes_only_on_a_rise(dma_write_ctrl_valid, dma_write_ctrl_data_index)) 
        else $error("dma_write_ctrl_data_index shouldn't change when dma_write_ctrl_valid is high");
    // CHECK dma_write_ctrl_data_size stability
    assert property (b_changes_only_on_a_rise(dma_write_ctrl_valid, dma_write_ctrl_data_size)) 
        else $error("dma_write_ctrl_data_size shouldn't change when dma_write_ctrl_valid is high");
    // CHECK dma_write_ctrl_data_user stability
    assert property (b_changes_only_on_a_rise(dma_write_ctrl_valid, dma_write_ctrl_data_user)) 
        else $error("dma_write_ctrl_data_user shouldn't change when dma_write_ctrl_valid is high");

    ////////   READ CONTROL ASSERTIONS   ////////
    // CHECK read_ctrl_valid read_ctrl_ready handshake
    assert property (@(posedge clk)
        disable iff (!rst)
        dma_read_ctrl_valid && dma_read_ctrl_ready |-> ##1 !dma_read_ctrl_valid
    ) else $error("dma_read_ctrl_valid should be low one cycle after dma_read_ctrl_valid && dma_read_ctrl_ready");
    // CHECK dma_read_ctrl_data_length stability
    assert property (b_changes_only_on_a_rise(dma_read_ctrl_valid, dma_read_ctrl_data_length)) 
        else $error("dma_read_ctrl_data_length shouldn't change when dma_read_ctrl_valid is high");
    // CHECK dma_read_ctrl_data_index stability
    assert property (b_changes_only_on_a_rise(dma_read_ctrl_valid, dma_read_ctrl_data_index)) 
        else $error("dma_read_ctrl_data_index shouldn't change when dma_read_ctrl_valid is high");
    // CHECK dma_read_ctrl_data_size stability
    assert property (b_changes_only_on_a_rise(dma_read_ctrl_valid, dma_read_ctrl_data_size)) 
        else $error("dma_read_ctrl_data_size shouldn't change when dma_read_ctrl_valid is high");
    // CHECK dma_read_ctrl_data_user stability
    assert property (b_changes_only_on_a_rise(dma_read_ctrl_valid, dma_read_ctrl_data_user)) 
        else $error("dma_read_ctrl_data_user shouldn't change when dma_read_ctrl_valid is high");

    ////////   WRITE ASSERTIONS   ////////
    initial begin
        int remaining;
        forever begin
            @(posedge clk iff dma_write_ctrl_ready && dma_write_ctrl_valid);
            remaining = dma_write_ctrl_data_length;
            @(posedge clk);
            if (remaining == 0) begin
                $error("dma_write_ctrl_data_length should be greater than 0");
            end

            fork
            begin : data_beats
                for (int i = 0; i < remaining; i++) begin
                @(posedge clk iff dma_write_chnl_ready && dma_write_chnl_valid);
                end
                remaining = 0;
            end

            begin : guard_new_start
                @(posedge clk iff dma_write_ctrl_ready && dma_write_ctrl_valid);
                #0;
                if (remaining > 0) begin
                $error("New ctrl before finishing previous transaction data");
                end
            end
            join_any
            disable fork;
        end
    end

    ////////   READ ASSERTIONS   ////////
    initial begin
        int remaining;
        forever begin
            @(posedge clk iff dma_read_ctrl_ready && dma_read_ctrl_valid);
            remaining = dma_read_ctrl_data_length;
            @(posedge clk);
            if (remaining == 0) begin
                $error("dma_read_ctrl_data_length should be greater than 0");
            end

            fork
            begin : data_beats
                for (int i = 0; i < remaining; i++) begin
                @(posedge clk iff dma_read_chnl_ready && dma_read_chnl_valid);
                end
                remaining = 0;
            end

            begin : guard_new_start
                @(posedge clk iff dma_read_ctrl_ready && dma_read_ctrl_valid);
                #0;
                if (remaining > 0) begin
                $error("New ctrl before finishing previous transaction data");
                end
            end
            join_any
            disable fork;
        end
    end



    task write_clean_trans(input logic [31:0] trans_length);
        logic [31:0] length;
        length = 0;

        dma_write_ctrl_ready = 1;
        dma_write_ctrl_valid = 1;
        dma_write_ctrl_data_length = trans_length;
        @(posedge clk) #0;
        dma_write_ctrl_valid = 0;
        dma_write_ctrl_ready = 0;
        
        while (length < trans_length) begin
            dma_write_chnl_valid = $urandom_range(0, 1);
            dma_write_chnl_ready = $urandom_range(0, 1);
            dma_write_chnl_data = $urandom_range(0, 64'hFFFFFFFFFFFFFFFF);
            @(posedge clk) #0;
            if (dma_write_chnl_valid && dma_write_chnl_ready) begin
                length++;
            end
        end

        dma_write_chnl_valid = 0;
        dma_write_chnl_ready = 0;
        repeat (1) @(posedge clk) #0;
    endtask

    task write_error_trans(input logic [31:0] trans_length);
        logic [31:0] length;
        length = $urandom_range(1, trans_length-1);

        dma_write_ctrl_ready = 1;
        dma_write_ctrl_valid = 1;
        dma_write_ctrl_data_length = trans_length;
        @(posedge clk) #0;
        dma_write_ctrl_valid = 0;
        dma_write_ctrl_ready = 0;
        
        while (length < trans_length) begin
            dma_write_chnl_valid = $urandom_range(0, 1);
            dma_write_chnl_ready = $urandom_range(0, 1);
            dma_write_chnl_data = $urandom_range(0, 64'hFFFFFFFFFFFFFFFF);
            @(posedge clk) #0;
            if (dma_write_chnl_valid && dma_write_chnl_ready) begin
                length++;
            end
        end

        dma_write_chnl_valid = 0;
        dma_write_chnl_ready = 0;
        repeat (1) @(posedge clk) #0;
    endtask


    initial begin
        clk = 0;
        forever #(t_clk/2) clk = ~clk;
    end

    initial begin
        rst = 0;
        acc_done = 0;
        dma_read_ctrl_valid = 0;
        dma_read_ctrl_ready = 0;
        dma_read_ctrl_data_length = 0;
        dma_read_ctrl_data_index = 0;
        dma_read_ctrl_data_size = 0;
        dma_read_ctrl_data_user = 0;
	    dma_read_chnl_ready = 0;
	    dma_read_chnl_valid = 0;
	    dma_read_chnl_data = 0;
	    dma_write_ctrl_ready = 0;
	    dma_write_ctrl_valid = 0;
	    dma_write_ctrl_data_index = 0;
	    dma_write_ctrl_data_length = 0;
	    dma_write_ctrl_data_size = 0;
	    dma_write_ctrl_data_user = 0;
	    dma_write_chnl_ready = 0;
	    dma_write_chnl_valid = 0;
	    dma_write_chnl_data = 0;
        repeat (2) @(posedge clk);
        rst = 1;
    end

    ////////////////////////
    /* stimulus section */
    ////////////////////////

    initial begin

        @(posedge rst);
        repeat (5) @(posedge clk);
    
    // CHECK acc_done pulse

        // acc_done = 0;
        // repeat (5) @(posedge clk);
        // acc_done = 1;
        // @(posedge clk);
        // acc_done = 0;
        // repeat (3) @(posedge clk);
        // acc_done = 1;
        // repeat (2) @(posedge clk);  // should trigger fatal
        // acc_done = 0;
        // repeat (5) @(posedge clk);

    // CHECK dma_read_ctrl_data_length stability

        // dma_read_ctrl_valid = 0;
        // dma_read_ctrl_data_length = 0;
        // repeat (7) @(posedge clk);
        // dma_read_ctrl_valid = 1;
        // dma_read_ctrl_data_length = 42;
        // repeat (5) @(posedge clk);
        // dma_read_ctrl_valid = 0;
        // dma_read_ctrl_data_length = 0;
        // repeat (3) @(posedge clk);
        // dma_read_ctrl_valid = 1;
        // dma_read_ctrl_data_length = 84;
        // repeat (4) @(posedge clk);
        // dma_read_ctrl_valid = 1;
        // dma_read_ctrl_data_length = 0;   // should trigger fatal
        // repeat (5) @(posedge clk);


        for (int i=0; i<100; ++i) begin
            if (i%2 == 0) begin
                write_clean_trans($urandom_range(4, 10));
            end else begin
                $display("-- Starting error transaction %0d --", i);
                write_error_trans($urandom_range(4, 10));
            end
        end

        
        $finish;
    end

endmodule



