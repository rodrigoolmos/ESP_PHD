`include "agent_acc_esp.sv"
`timescale 1us/1ns

module tb_general_acc_esp;
    
    const integer t_clk    = 10;    // Clock period 100MHz

    const bit[63:0] vec_a[16] = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15};
    const bit[63:0] vec_b[16] = {10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25};
    bit[63:0] gold[16];
    bit[63:0] result_acc[];

    bit error_acc;

    esp_acc_if esp_acc_if_inst();

    agent_esp_acc agent_esp_acc_inst;

    test_rtl_basic_dma64 test_rtl_basic_dma64_inst(
        .clk(esp_acc_if_inst.clk),
        .rst_n(esp_acc_if_inst.rst),
        .conf_info_reg0(esp_acc_if_inst.conf_info_reg0),
        .conf_info_reg1(esp_acc_if_inst.conf_info_reg1),
        .conf_done(esp_acc_if_inst.conf_done),
        .acc_done(esp_acc_if_inst.acc_done),
        .debug(esp_acc_if_inst.debug),
        .dma_read_ctrl_ready(esp_acc_if_inst.dma_read_ctrl_ready),
        .dma_read_ctrl_valid(esp_acc_if_inst.dma_read_ctrl_valid),
        .dma_read_ctrl_data_index(esp_acc_if_inst.dma_read_ctrl_data_index),
        .dma_read_ctrl_data_length(esp_acc_if_inst.dma_read_ctrl_data_length),
        .dma_read_ctrl_data_size(esp_acc_if_inst.dma_read_ctrl_data_size),
        .dma_read_ctrl_data_user(esp_acc_if_inst.dma_read_ctrl_data_user),
        .dma_read_chnl_ready(esp_acc_if_inst.dma_read_chnl_ready),
        .dma_read_chnl_valid(esp_acc_if_inst.dma_read_chnl_valid),
        .dma_read_chnl_data(esp_acc_if_inst.dma_read_chnl_data),
        .dma_write_ctrl_ready(esp_acc_if_inst.dma_write_ctrl_ready),
        .dma_write_ctrl_valid(esp_acc_if_inst.dma_write_ctrl_valid),
        .dma_write_ctrl_data_index(esp_acc_if_inst.dma_write_ctrl_data_index),
        .dma_write_ctrl_data_length(esp_acc_if_inst.dma_write_ctrl_data_length),
        .dma_write_ctrl_data_size(esp_acc_if_inst.dma_write_ctrl_data_size),
        .dma_write_ctrl_data_user(esp_acc_if_inst.dma_write_ctrl_data_user),
        .dma_write_chnl_ready(esp_acc_if_inst.dma_write_chnl_ready),
        .dma_write_chnl_valid(esp_acc_if_inst.dma_write_chnl_valid),
        .dma_write_chnl_data(esp_acc_if_inst.dma_write_chnl_data)
    );

    initial begin
        esp_acc_if_inst.clk = 0;
        forever #(t_clk/2) esp_acc_if_inst.clk = 
                    ~esp_acc_if_inst.clk;
    end

    initial begin
        agent_esp_acc_inst = new(esp_acc_if_inst);
        esp_acc_if_inst.rst = 0;
        #100 @(posedge esp_acc_if_inst.clk);
        esp_acc_if_inst.rst = 1;
        @(posedge esp_acc_if_inst.clk);
    end

    initial begin
        @(posedge esp_acc_if_inst.rst);

        agent_esp_acc_inst.load_memory(0, 16, vec_a);
        agent_esp_acc_inst.load_memory(16, 16, vec_b);
        agent_esp_acc_inst.run(0, 16);
        agent_esp_acc_inst.collect_memory(0, 16, result_acc);
        agent_esp_acc_inst.gold_gen(vec_a, vec_b, gold);
        error_acc = agent_esp_acc_inst.validate_acc(result_acc, gold, 16);
        assert (!error_acc)
            else $error("Error: Validation failed!");


        agent_esp_acc_inst.load_memory(0, 16, vec_a);
        agent_esp_acc_inst.load_memory(16, 16, vec_b);
        agent_esp_acc_inst.run(0, 16);
        agent_esp_acc_inst.collect_memory(0, 16, result_acc);
        agent_esp_acc_inst.gold_gen(vec_a, vec_b, gold);
        error_acc = agent_esp_acc_inst.validate_acc(result_acc, gold, 16);
        assert (!error_acc)
            else $error("Error: Validation failed!");

        $finish;

    end

endmodule