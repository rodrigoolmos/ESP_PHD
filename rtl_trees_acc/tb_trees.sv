`timescale 1ns / 1ps

module tb_trees;

    const integer t_clk    = 10;    // Clock period 100MHz


    // Parámetros
    parameter N_TREES          = 128;
    parameter N_NODES          = 256;
    parameter N_FEATURE        = 32;
    parameter TREES_LEN_BITS   = $clog2(N_NODES);
    parameter TREE_IDX_BITS    = $clog2(N_TREES);

    parameter N_SAMPLES = 10000;    // Number of samples
    parameter COLUMNAS = 33;        // 32 features + 1 label

    parameter N_64_FEATURES = N_SAMPLES/2*(COLUMNAS-1);

    // Memorias
    bit [63:0] trees            [N_TREES*N_NODES-1:0];
    bit [63:0] features_mem_64  [N_64_FEATURES-1:0];
    bit [31:0] labels_mem       [N_SAMPLES-1:0];

    // Señales
    logic clk;
    logic rst_n;
    logic start;

    logic load_trees;
    logic [TREES_LEN_BITS-1:0] n_node;
    logic [TREE_IDX_BITS-1:0]  n_tree;
    logic [63:0] tree_nodes;

    logic load_features;
    logic [31:0] n_feature;
    logic [63:0] features2;

    logic signed [31:0] prediction;
    logic done;

    // Instancia del DUT
    trees #(
        .N_TREES(N_TREES),
        .N_NODE_AND_LEAFS(N_NODES),
        .N_FEATURE(N_FEATURE)
    ) trees_ins (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .load_trees(load_trees),
        .n_node(n_node),
        .n_tree(n_tree),
        .tree_nodes(tree_nodes),
        .load_features(load_features),
        .n_feature(n_feature),
        .features2(features2),
        .prediction(prediction),
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

    task coppy_features(int n_features);
        for (int i = 0; i < n_features; i++) begin
            features2 = features_mem_64[i];
            n_feature = 2*i;
            load_features = 1;
            @(posedge clk);
            load_features = 0;
        end
    endtask

    task coppy_trees(int n_trees, int n_nodes);
        for (int i = 0; i < n_trees; i++) begin
            for (int j = 0; j < n_nodes; j++) begin
                tree_nodes = trees[i*n_nodes + j];
                n_tree = i;
                n_node = j;
                load_trees = 1;
                @(posedge clk);
                load_trees = 0;
            end
        end
    endtask

    // Clock generation
    initial begin
        clk = 0;
        forever #(t_clk/2) clk = ~clk;
    end

  // Estímulo principal
  initial begin
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
    read_features("/home/rodrigo/Documents/ESP_PHD/rtl_trees_acc/dataset_caracterizacion_frec.dat", features_mem_64, labels_mem);
    coppy_features(N_64_FEATURES);

    // Iniciar la predicción
    start = 1;
    @(posedge clk);
    start = 0;

    // Esperar a que se complete la predicción
    #100ns;
    while (!done) begin
        @(posedge clk);
    end

    // Mostrar el resultado de la predicción
    $display("Predicción: %d", prediction);

    // Finalizar simulación
    $finish;
  end

endmodule
