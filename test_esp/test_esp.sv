module test_esp;

    parameter t_clk = 10;

    logic clk;
    logic rst;
    logic acc_done;

	// DMA read control
    logic        dma_read_ctrl_valid;
	logic        dma_read_ctrl_ready;
    logic [31:0] dma_read_ctrl_data_length;


    ////////////////////////
    /* assertions section */
    ////////////////////////

    // CHECK acc_done pulse
    assert property (@(posedge clk)
        disable iff (!rst)
        $rose(acc_done) |-> ##1 !acc_done
    ) else $error("acc_done pulse should be one cycle only");

    // CHECK dma_read_ctrl_data_length stability
    property b_changes_only_on_a_rise(logic sigA, logic [31:0] sigB);
        @(posedge clk) disable iff (!rst)
            $changed(sigB) |-> $changed(sigA) || !sigA;
    endproperty
    assert property (b_changes_only_on_a_rise(dma_read_ctrl_valid, dma_read_ctrl_data_length)) 
        else $error("dma_read_ctrl_data_length shouldn't change when dma_read_ctrl_valid is high");
    

    initial begin
        clk = 0;
        forever #(t_clk/2) clk = ~clk;
    end

    initial begin
        rst = 0;
        repeat (2) @(posedge clk);
        rst = 1;
    end

    ////////////////////////
    /* stimulus section */
    ////////////////////////

    initial begin
    
    // CHECK acc_done pulse

        acc_done = 0;
        repeat (5) @(posedge clk);
        acc_done = 1;
        @(posedge clk);
        acc_done = 0;
        repeat (3) @(posedge clk);
        acc_done = 1;
        repeat (2) @(posedge clk);  // should trigger fatal
        acc_done = 0;
        repeat (5) @(posedge clk);

    // CHECK dma_read_ctrl_data_length stability

        dma_read_ctrl_valid = 0;
        dma_read_ctrl_data_length = 0;
        repeat (7) @(posedge clk);
        dma_read_ctrl_valid = 1;
        dma_read_ctrl_data_length = 42;
        repeat (5) @(posedge clk);
        dma_read_ctrl_valid = 0;
        dma_read_ctrl_data_length = 0;
        repeat (3) @(posedge clk);
        dma_read_ctrl_valid = 1;
        dma_read_ctrl_data_length = 84;
        repeat (4) @(posedge clk);
        dma_read_ctrl_valid = 1;
        dma_read_ctrl_data_length = 0;   // should trigger fatal
        repeat (5) @(posedge clk);
        $finish;
    end

endmodule



