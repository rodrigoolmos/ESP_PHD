`timescale 1ns / 1ps

module tb_trees_ping_pong;

    const integer t_clk    = 10;    // Clock period 100MHz

    // Parámetros
    parameter N_TREES          = 128;
    parameter N_NODES          = 256;
    parameter N_FEATURE        = 32;
    parameter HALF_FEATURE     = N_FEATURE/2;
    parameter MAX_BURST        = 54;
    parameter TREES_LEN_BITS   = $clog2(N_NODES);
    parameter TREE_IDX_BITS    = $clog2(N_TREES);
    parameter MAX_BURST_BITS    = $clog2(MAX_BURST);

    parameter N_SAMPLES        = 10000;    // Number of samples
    parameter COLUMNAS         = 33;        // 32 features + 1 label

    parameter N_64_FEATURES    = N_SAMPLES/2*(COLUMNAS-1);

    // Memorias
    bit [63:0]      trees            [N_TREES*N_NODES-1:0];
    bit [63:0]      features_mem_64  [N_64_FEATURES-1:0];
    bit [31:0]      labels_mem       [N_SAMPLES-1:0];
    bit [7:0]       predictions_hw   [N_SAMPLES-1:0];

    // Señales
    logic clk;
    logic rst_n;
    logic start;

    logic load_trees;
    logic [TREES_LEN_BITS-1:0] n_node;
    logic [TREE_IDX_BITS-1:0]  n_tree;
    logic [63:0] tree_nodes;

    logic load_features;
    logic [31:0] feature_addr;
    logic [MAX_BURST_BITS-1:0] burst_len;
    logic [63:0] features2;

    logic [63:0] prediction;
    logic [MAX_BURST_BITS-1:0] prediction_addr;
    logic done;

    // variables
    int                                 offset = 0; // Offset for features
    bit [31:0]                          predictions_sw[N_SAMPLES-1:0];


    // Instancia del DUT
    trees_ping_pong #(
        .N_TREES(N_TREES),
        .N_NODE_AND_LEAFS(N_NODES),
        .N_FEATURE(N_FEATURE),
        .MAX_BURST(MAX_BURST)
    ) trees_ping_pong_ins (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),

        .load_trees(load_trees),
        .n_node(n_node),
        .n_tree(n_tree),
        .tree_nodes(tree_nodes),

        .load_features(load_features),
        .feature_addr(feature_addr),
        .burst_len(burst_len),
        .features2(features2),

        .prediction(prediction),
        .prediction_addr(prediction_addr),
        .done(done)
    );

    task automatic read_trees(
        input string nombre_archivo,
        output bit [63:0] datos [N_TREES*N_NODES-1:0]
      );
        integer file, status;
        begin
          file = $fopen(nombre_archivo, "r");
          if (file == 0) begin
            $display("ERROR: No se pudo abrir el archivo: %s", nombre_archivo);
            $finish;
          end
    
          for (int i = 0; i < N_TREES; i++) begin
            for (int j = 0; j < N_NODES; j++) begin
              status = $fscanf(file, "0x%h ", datos[i*N_NODES+j]);
              if (status != 1) begin
                $display("ERROR: Lectura fallida en [%0d][%0d]", i, j);
                $fclose(file);
                $finish;
              end
            end
          end
          $fclose(file);
        end
    endtask

    task read_features(
        input  string nombre_archivo,
        output bit [63:0] features [N_64_FEATURES-1:0],           // 32 columnas
        output bit [31:0] labels   [N_SAMPLES-1:0]              // última columna
    );
        integer file, status;
        shortreal temp_float_l;
        shortreal temp_float_h;
        int temp_int;
        bit [31:0] temp_float_32_l;
        bit [31:0] temp_float_32_h;

        file = $fopen(nombre_archivo, "r");
        if (file == 0) begin
        $display("ERROR: No se pudo abrir el archivo: %s", nombre_archivo);
        $finish;
        end

        for (int i = 0; i < N_SAMPLES; i++) begin
            for (int j = 0; j < (COLUMNAS-1)/2; j++) begin
                status = $fscanf(file, "%f ", temp_float_l); // ← %f + shortreal
                if (status != 1) begin
                    $display("ERROR leyendo feature[%0d][%0d]", i, j);
                    $finish;
                end               
                status = $fscanf(file, "%f ", temp_float_h); // ← %f + shortreal
                if (status != 1) begin
                    $display("ERROR leyendo feature[%0d][%0d]", i, j);
                    $finish;
                end
                temp_float_32_l = $shortrealtobits(temp_float_l); // ← binario exacto
                temp_float_32_h = $shortrealtobits(temp_float_h); // ← binario exacto
                features[i*(COLUMNAS-1)/2 + j] = {temp_float_32_h, temp_float_32_l}; // ← 64 bits
            end
            
            // Leer la etiqueta como entero (si es 0 o 1, por ejemplo)
            status = $fscanf(file, "%d\n", temp_int);
            if (status != 1) begin
                $display("ERROR leyendo label[%0d]", i);
                $finish;
            end
            labels[i] = temp_int;
        end

        $fclose(file);
    endtask

    task coppy_features(int n_features, int offset = 0);
        load_features = 1;
        for (int i = 0; i < n_features; i++) begin
            features2 = features_mem_64[i + offset];
            feature_addr = i;
            @(posedge clk);
        end
        load_features = 0;
    endtask

    task coppy_trees(int n_trees, int n_nodes);
        load_trees = 1;
        for (int i = 0; i < n_trees; i++) begin
            for (int j = 0; j < n_nodes; j++) begin
                tree_nodes = trees[i*n_nodes + j];
                n_tree = i;
                n_node = j;
                @(posedge clk);
            end
        end
        load_trees = 0;
    endtask

    task read_predictions(int n_predictions);
        int i, j;
        for (i = 0; i < n_predictions/8; i++) begin
            prediction_addr = i;
            @(posedge clk);
            for (j=0; j<8; ++j) begin
                predictions_hw[i*8+j+offset] = prediction[8*j+: 8];
                $display("Predicción %0d: %0d", i*8+j+offset, predictions_hw[i*8+j+offset]);
            end
        end
        prediction_addr = i;
        @(posedge clk);
        for (j=0; j<n_predictions%8; ++j) begin
            predictions_hw[i*8+j+offset] = prediction[8*j+: 8];
            $display("Predicción %0d: %0d", i*8+j+offset, predictions_hw[i*8+j+offset]);
        end

        offset = offset + n_predictions;
    endtask

    task launch_prediction(int burst_l = MAX_BURST);

        coppy_features(burst_l*HALF_FEATURE, offset*HALF_FEATURE);

        // Iniciar la predicción
        start = 1;
        burst_len = burst_l; // Longitud del burst
        @(posedge clk);
        start = 0;

        // Esperar a que se complete la predicción
        while (!done) begin
            @(posedge clk);
        end
        repeat (100) @(posedge clk);

        // Mostrar el resultado de las predicciones
        read_predictions(burst_l);
    endtask

    task automatic gold_gen(input bit[63:0] trees [N_NODES*N_TREES-1:0], 
                            input integer n_features, 
                            input bit [63:0] features[N_64_FEATURES-1:0], 
                            input bit [31:0] labels[N_SAMPLES-1:0], 
                            ref   bit [31:0] predictions_sw[N_SAMPLES-1:0]);

        logic[31:0] sum = 0;
        logic[31:0] leaf_value;
        logic[31:0] counts[32];
        logic[7:0]  node_index;
        logic[7:0]  node_right;
        logic[7:0]  node_left;
        logic[7:0]  feature_index;
        logic[31:0] threshold;
        logic[63:0] node;
        logic[31:0] best;
        logic[31:0] best_count;
        logic[31:0] feature_h;
        logic[31:0] feature_l;

        integer correct = 0;

        for (int p=0; p<N_SAMPLES; ++p) begin
            for (int c=0; c<32; ++c)
                counts[c] = 0;

                for (int t = 0; t < N_TREES; t++) begin
                node_index = 0;
    
                while(1) begin
                    node = trees[t*N_NODES+node_index];
                    feature_index = node[15:8];
                    threshold = node[63:32];
                    node_left = node_index + 1;
                    node_right = node[23:16];
                    
                    {feature_h, feature_l} = features[p*n_features/2+feature_index/2];
                    
                    if (feature_index%2) begin
                        node_index = feature_h < threshold ? 
                                                node_left : node_right;
                    end else begin
                        node_index = feature_l < threshold ? 
                                                node_left : node_right;
                    end
    
                    if (!(node[0]))
                        break;
                end
    
                leaf_value = node[63:32];
                if (leaf_value >= 0 && leaf_value < 32)
                    counts[leaf_value]++;
    
                end
    
            // Busca la clase ganadora
            best      = 0;
            best_count = counts[0];
            for (int c = 1; c < 32; c++) begin
                
                if (counts[c] > best_count) begin
                    best_count = counts[c];
                    best       = c;
                end
            end
    
            predictions_sw[p] = best;            
        end

        // Imprime los resultados
        for (int p = 0; p < 10000; ++p) begin
            if (labels[p] == predictions_sw[p]) begin
                correct++;
            end
        end

        $display("Correct predictions: %0d de %0d", correct, 10000);
        $display("Accuracy: %f", (correct / 10000.0));

    endtask

    // Clock generation
    initial begin
        clk = 0;
        forever #(t_clk/2) clk = ~clk;
    end

  // Estímulo principal
  initial begin
    int data_processed;
    int samples_2_process;
    rst_n = 0;
    start = 0;
    load_trees = 0;
    load_features = 0;

    // Esperar un ciclo de reloj
    @(posedge clk);
    rst_n = 1;

    // Leer árboles y características desde archivos
    read_trees("/home/rodrigo/Documents/ESP_PHD/rtl_trees_acc/model_caracterizacion_frec.dat", trees);
    coppy_trees(N_TREES, N_NODES);
    read_features("/home/rodrigo/Documents/ESP_PHD/rtl_trees_acc/dataset_caracterizacion_frec_shuffled.dat", features_mem_64, labels_mem);

    // Generar predicciones de referencia
    gold_gen(trees, N_FEATURE, features_mem_64, labels_mem, predictions_sw);

    while (data_processed < N_SAMPLES) begin
        samples_2_process = $urandom_range(1, MAX_BURST);
        if ((data_processed + samples_2_process) >= N_SAMPLES) begin
            samples_2_process = N_SAMPLES - data_processed;
        end
        $display("Data processed: %0d, Samples to process: %0d", data_processed, samples_2_process);
        launch_prediction(samples_2_process);
        data_processed += samples_2_process;
    end

    for (int num_sets=0; num_sets<N_SAMPLES; ++num_sets) begin
        assert (predictions_sw[num_sets] == predictions_hw[num_sets])
            else begin
                $error("Assert predictions_sw != predictions_hw failed!");
                $display("predictions_sw[%0d] = %0d, predictions_hw[%0d] = %0d", 
                         num_sets, predictions_sw[num_sets], num_sets, predictions_hw[num_sets]);
                //$stop;
            end
    end

    // Finalizar simulación
    $finish;
  end

endmodule
