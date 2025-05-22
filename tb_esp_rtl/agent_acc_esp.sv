interface esp_acc_if;

    logic clk;                              // Main clock signal for the accelerator (provided by ESP socket)
    logic rst;                              // Active-low synchronous reset signal (provided by ESP socket)

    // << User-defined configuration registers >>
    logic [31:0] conf_info_reg0;            // Configuration register 0 (typically used as read data index)
    logic [31:0] conf_info_reg1;            // Configuration register 1 (typically used as read data length)

    logic conf_done;                        // One-cycle pulse indicating that configuration registers are valid

    logic acc_done;                         // One-cycle pulse from the accelerator indicating completion
    logic [31:0] debug;                     // Optional debug output (e.g., error codes, FSM state)

    // DMA Read Control – signals for initiating a DMA read transaction
    logic dma_read_ctrl_ready;              // From socket: high when ready to accept a new read request
    logic dma_read_ctrl_valid;              // From accelerator: high when issuing a read request
    logic [31:0] dma_read_ctrl_data_index;  // Offset (in beats) from the base of the virtual memory region
    logic [31:0] dma_read_ctrl_data_length; // Number of beats to read
    logic [2:0] dma_read_ctrl_data_size;    // Beat size encoding (e.g., 011 = 64-bit)
    logic [5:0] dma_read_ctrl_data_user;    // User-defined field to select source (e.g., memory, P2P, multicast)

    // DMA Read Channel – signals for receiving data from memory
    logic dma_read_chnl_ready;              // From accelerator: high when ready to receive data
    logic dma_read_chnl_valid;              // From socket: high when data is available
    logic [63:0] dma_read_chnl_data;        // Data beat received from memory (typically 64-bit)

    // DMA Write Control – signals for initiating a DMA write transaction
    logic dma_write_ctrl_ready;             // From socket: high when ready to accept a new write request
    logic dma_write_ctrl_valid;             // From accelerator: high when issuing a write request
    logic [31:0] dma_write_ctrl_data_index; // Offset (in beats) from the base of the virtual memory region
    logic [31:0] dma_write_ctrl_data_length;// Number of beats to write
    logic [2:0] dma_write_ctrl_data_size;   // Beat size encoding (e.g., 011 = 64-bit)
    logic [5:0] dma_write_ctrl_data_user;   // User-defined field to select target (e.g., memory, P2P, multicast)

    // DMA Write Channel – signals for sending data to memory
    logic dma_write_chnl_ready;             // From socket: high when ready to receive write data
    logic dma_write_chnl_valid;             // From accelerator: high when write data is valid
    logic [63:0] dma_write_chnl_data;       // Data beat sent to memory (typically 64-bit)

endinterface

class agent_esp_acc;

    // Virtual interface to the DUT (ESP accelerator)
    virtual esp_acc_if esp_if;

    // Local storage for read and write parameters
    int unsigned read_index;
    int unsigned read_length;
    int unsigned write_index;
    int unsigned write_length;

    // Simulated memory array
    bit [63:0] mem[*];

    // Constructor: bind the interface and reset relevant signals
    function new(virtual esp_acc_if esp_if);
        this.esp_if = esp_if;
        esp_if.conf_done             = 0;
        esp_if.dma_read_ctrl_ready   = 0;
        esp_if.dma_read_chnl_valid   = 0;
        esp_if.dma_write_ctrl_ready  = 0;
        esp_if.dma_write_chnl_ready  = 0;
    endfunction

    // Load a contiguous block of 64-bit data into simulated memory
    task load_memory(input int unsigned base, input int unsigned length, input bit [63:0] data[]);
        for (int i = 0; i < length; i++) begin
            mem[base + i] = data[i];
            $display("Loading data %0h into memory at index %0d", data[i], base + i);
            $display("Memory[%0d] = %0h", base + i, mem[base + i]);
        end
    endtask

    // Extract a block of data from simulated memory
    task automatic collect_memory(input int unsigned base, input int unsigned length, ref bit [63:0] data[]);
        data = new[length];
        for (int i = 0; i < length; i++) begin
            data[i] = mem[base + i];
            $display("Collecting data %0h from memory at index %0d", data[i], base + i);
            $display("Memory[%0d] = %0h", base + i, mem[base + i]);
        end
    endtask

    // Drive the full accelerator transaction
    task run(input int unsigned cfg_index, input int unsigned cfg_length);
        // CONFIG PHASE: apply registers
        esp_if.conf_info_reg0 = cfg_index;          // CONFIG example
        esp_if.conf_info_reg1 = cfg_length;         // CONFIG example
        @(posedge esp_if.clk);
        esp_if.conf_done      = 1;
        @(posedge esp_if.clk);
        esp_if.conf_done      = 0;

        // READ CONTROL: handshake
        esp_if.dma_read_ctrl_ready = 1;
        @(posedge esp_if.clk);
        wait (esp_if.dma_read_ctrl_valid && esp_if.dma_read_ctrl_ready);
        read_index  = esp_if.dma_read_ctrl_data_index;
        read_length = esp_if.dma_read_ctrl_data_length;
        esp_if.dma_read_ctrl_ready = 0;

        // READ CHANNEL: supply data beats
        esp_if.dma_read_chnl_valid = 1;
        for (int i = 0; i < read_length; ) begin
            esp_if.dma_read_chnl_data = mem[read_index + i];
            $display("Sending data %0h to read channel", esp_if.dma_read_chnl_data);
            i++;
            @(posedge esp_if.clk iff esp_if.dma_read_chnl_ready && esp_if.dma_read_chnl_valid);
        end
        esp_if.dma_read_chnl_valid = 0;
        @(posedge esp_if.clk);

        // WRITE CONTROL: handshake
        esp_if.dma_write_ctrl_ready = 1;
        @(posedge esp_if.clk);
        wait (esp_if.dma_write_ctrl_valid && esp_if.dma_write_ctrl_ready);
        write_index  = esp_if.dma_write_ctrl_data_index;
        write_length = esp_if.dma_write_ctrl_data_length;
        esp_if.dma_write_ctrl_ready = 0;

        // WRITE CHANNEL: capture returned data
        esp_if.dma_write_chnl_ready = 1;
        for (int i = 0; i < write_length; ) begin
            @(posedge esp_if.clk iff esp_if.dma_write_chnl_ready && esp_if.dma_write_chnl_valid);
            mem[write_index + i] = esp_if.dma_write_chnl_data;
            $display("Received data %0h from write channel", esp_if.dma_write_chnl_data);
            i++;
        end
        esp_if.dma_write_chnl_ready = 0;
        @(posedge esp_if.clk);

        // WAIT for accelerator to assert acc_done
        wait (esp_if.acc_done == 1);
    endtask

    // Validate the results against a gold standard
    function bit validate_acc(input bit [63:0] result_acc[], input bit [63:0] gold[], input int unsigned length);
        for (int i = 0; i < length; i++) begin
            if (result_acc[i] != gold[i]) begin
                $display("Mismatch at index %0d: expected %0h, got %0h", i, gold[i], result_acc[i]);
                return 1;
            end
        end
        return 0;
    endfunction

    // Generate a gold standard for the expected output
    task gold_gen(input bit [63:0] vec_a[16], input bit [63:0] vec_b[16], ref bit [63:0] gold[16]);
        for (int i = 0; i < 16; i++)
                gold[i] = vec_a[i] + vec_b[i];
    endtask

endclass
