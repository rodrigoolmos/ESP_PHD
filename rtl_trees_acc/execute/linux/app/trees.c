// Copyright (c) 2011-2024 Columbia University, System Level Design Group
// SPDX-License-Identifier: Apache-2.0
#include "libesp.h"
#include "cfg.h"
#include "monitors.h"

static unsigned in_words_adj;
static unsigned out_words_adj;
static unsigned in_len;
static unsigned out_len;
static unsigned in_size;
static unsigned out_size;
static unsigned out_offset;
static unsigned size;

union stamps{
    uint32_t clk[2];
    uint64_t data;
};

int read_n_features(const char *csv_file, int n, struct feature *features, 
                    token_t *features_buff[MAX_BURST*N_FEATURE]) {
    FILE *file = fopen(csv_file, "r");
    char line[MAX_LINE_LENGTH];
    int read_samples = 0;
    int i, block_i, local_i;
    float* ptr_32;

    if (!file) {
        printf("Failed to open the features file %s\n", csv_file);
        return -1;
    }

    
    while (fgets(line, MAX_LINE_LENGTH, file) && read_samples < n) {
        block_i = read_samples/MAX_BURST;
        local_i = read_samples%MAX_BURST;
        // Set the pointer to the new block of features
        ptr_32 = (float*)features_buff[block_i];
        float temp[N_FEATURE + 1];
        char *token = strtok(line, ",");
        int index = 0;

        while (token != NULL && index < N_FEATURE + 1) {
            temp[index] = atof(token);
            token = strtok(NULL, ",");
            index++;
        }

        for (i = 0; i < index - 1; i++) {
            features[read_samples].features[i] = temp[i];
            // Store the features in the block
            ptr_32[local_i * N_FEATURE + i]  = temp[i];
        }
        features[read_samples].prediction = (uint8_t) temp[index - 1];

        read_samples++;
    }

    fclose(file);
    printf("Read %d features from %s\n", read_samples, csv_file);
    return read_samples;
}

void load_model(token_t *tree_buf, const char *filename)
{
    char magic_number[5] = {0};
    FILE *file = fopen(filename, "rb");
    if (file == NULL) {
        printf("Error opening the model file %s\n", filename);
        return;
    }

    fread(magic_number, 5, 1, file);

    if (!memcmp(magic_number, "model", 5)) {
        for (int t = 0; t < N_TREES; t++) {
            for (int n = 0; n < N_NODE_AND_LEAFS; n++) {
                fread(&tree_buf[t * N_NODE_AND_LEAFS + n], sizeof(uint64_t), 1, file);
                if (t == 0 && n == 0){
                    printf("Dato en sdad hexadecimal: 0x%" PRIx64 "\n", tree_buf[0]);
                }
            }
        }
    }
    else {
        printf("Unknown file type\n");
    }

    printf("Loaded model from %s\n", filename);

    fclose(file);
}

/* User-defined code */
static void init_parameters()
{
    in_words_adj  = round_up(10000*32, DMA_WORD_PER_BEAT(sizeof(token_t)));
    out_words_adj = round_up(10000/4 , DMA_WORD_PER_BEAT(sizeof(token_t)));

    in_len     = in_words_adj * (1);
    out_len    = out_words_adj * (1);
    in_size    = in_len * sizeof(token_t);
    out_size   = out_len * sizeof(token_t);
    out_offset = in_len;
    size       = (out_offset * sizeof(token_t)) + out_size;
}

void send_trees(token_t *buf)
{
    
    union stamps u_stamps;

    printf("Sending trees...\n");
    trees_cfg_000[0].burst_len = 0;
    trees_cfg_000[0].load_trees = 1;
    cfg_000[0].hw_buf                 = buf;
    esp_run(cfg_000, NACC);
    memcpy(&u_stamps.data, &buf[0], sizeof(uint64_t));
    printf(" - Send trees clock stamps: send %i, process %i clk cicles\n", u_stamps.clk[1], u_stamps.clk[0]);

}

void perform_inferences_hw(token_t *buf, int read_samples, uint8_t *predictions, 
                            float *exe_time_ms)
{

    esp_monitor_args_t mon_args = {
        .read_mode  = ESP_MON_READ_ALL,
        .read_mask  = 0,                  // no usado en READ_ALL
        .tile_index = 2,                  // ej.: tile (1,0) => índice 2
        .acc_index  = 0,                  // no usado en READ_ALL
        .mon_index  = 0,                  // no usado en READ_ALL
        .noc_index  = 0                   // no usado en READ_ALL
    };

    struct timespec startn, endn;
    esp_monitor_vals_t vals_start, vals_end, vals_diff;
    unsigned long long hw_ns;
    union stamps u_stamps;

    printf("Performing inferences...\n");
    esp_monitor(mon_args, &vals_start);
    gettime(&startn);
    trees_cfg_000[0].burst_len = read_samples;
    trees_cfg_000[0].load_trees = 0;
    cfg_000[0].hw_buf = buf;
    esp_run(cfg_000, NACC);
    gettime(&endn);
    esp_monitor(mon_args, &vals_end);
    hw_ns = ts_subtract(&startn, &endn);
    *exe_time_ms = hw_ns/1000000.0;
    printf("  > Hardware test time: %f ms\n", *exe_time_ms);
    
    vals_diff = esp_monitor_diff(vals_start, vals_end);
    FILE *fp = fopen("Trees_esp_mon_all.txt", "w");
    esp_monitor_print(mon_args, vals_diff, fp);
    fclose(fp);

    memcpy(predictions, buf, read_samples);

    memcpy(&u_stamps.data, &buf[read_samples/8], sizeof(uint64_t));
    printf(" - Process features clock stamps: send %i, process %i clk cicles\n", u_stamps.clk[1], u_stamps.clk[0]);

}

void print_accuracy(struct feature *features, uint8_t *predictions, 
                        int read_samples, int n_classes)
{

    int accuracy[256]   = {0};
    int accuracy_total  = 0;
    int evaluated[256]  = {0};
    int evaluated_total = 0;

    for (size_t i = 0; i < read_samples/8; i++) {
        for (size_t k = 0; k < 8; k++){

            if (features[i*8+k].prediction == predictions[i*8+k]) {
                accuracy[features[i*8+k].prediction]++;
                accuracy_total++;
            }
            evaluated[features[i*8+k].prediction]++;
            evaluated_total++;
        }
    }

    for (int i = 0; i <= n_classes; i++) {
        printf("Accuracy %f class %i num instances %i\n", 1.0 * accuracy[i] / evaluated[i], i,
               evaluated[i]);
    }

    printf("Accuracy total %f evaluates samples %i of %i\n", 1.0 * accuracy_total / read_samples,
           evaluated_total, read_samples);
}

void evaluate_model(token_t *trees_buf, token_t *features_buf[MAX_BURST],  struct feature *features, int read_samples, int n_classes,
                    uint8_t *predictions, uint32_t max_burst, float *exe_time_ms)
{
    uint32_t processed = 0;
    uint32_t burst, burst_i=0;
    float exe_t;
    *exe_time_ms = 0;

    send_trees(trees_buf);

    while (processed < read_samples) {
        burst =
            (read_samples - processed) > max_burst ? max_burst : (read_samples - processed);
        printf("Processing batch %i, processed %i of %i\n", burst, processed, read_samples);
        perform_inferences_hw(features_buf[burst_i],
                                burst, &predictions[processed], &exe_t);
        *exe_time_ms += exe_t;
        processed += burst;
        burst_i++;
    }

    print_accuracy(features, predictions, read_samples, n_classes);
}

void make_prediction(token_t *tree, float features[N_FEATURE], int32_t *prediction)
{
    int32_t leaf_value;
    int32_t counts[N_CLASSES] = {0};

    for (int t = 0; t < N_TREES; t++) {
        uint8_t node_index = 0;
        uint8_t node_right;
        uint8_t node_left;
        uint8_t feature_index;
        float threshold;
        tree_data tree_data;

        while (1) {
            tree_data.compact_data = tree[t * N_NODE_AND_LEAFS + node_index];
            feature_index          = tree_data.tree_camps.feature_index;
            threshold              = tree_data.tree_camps.float_int_union.f;
            node_left              = node_index + 1;
            node_right             = tree_data.tree_camps.next_node_right_index;

            node_index = *(int32_t *)&features[feature_index] < *(int32_t *)&threshold ? node_left :
                                                                                         node_right;

            if (!(tree_data.tree_camps.leaf_or_node & 0x01)) break;
        }

        leaf_value = tree_data.tree_camps.float_int_union.i;
        if (leaf_value >= 0 && leaf_value < N_CLASSES) { counts[leaf_value]++; }
    }

    // Busca la clase ganadora
    int32_t best       = 0;
    int32_t best_count = counts[0];

    for (int c = 1; c < N_CLASSES; c++) {
        if (counts[c] > best_count) {
            best_count = counts[c];
            best       = c;
        }
    }

    *prediction = best;
}

void software_prediction(struct feature *features, int read_samples,
                            token_t* tree, int n_classes, uint8_t *predictions_sw, 
                            float *exe_time_ms)
{
    int32_t prediction;
    int accuracy[256]   = {0};
    int accuracy_total  = 0;
    int evaluated[256]  = {0};
    int evaluated_total = 0;
    struct timespec startn, endn;
    unsigned long long sw_ns;

    gettime(&startn);
    for (size_t i = 0; i < read_samples; i++) {
        make_prediction(tree, features[i].features, &prediction);
        if (features[i].prediction == prediction) {
            accuracy[features[i].prediction]++;
            accuracy_total++;
        }
        predictions_sw[i] = prediction;
        

        evaluated[features[i].prediction]++;
        evaluated_total++;
    }
    gettime(&endn);
    sw_ns = ts_subtract(&startn, &endn);
    *exe_time_ms = sw_ns/1000000.0;
    printf("  > Software test time: %f ms\n", *exe_time_ms);

    for (int i = 0; i <= n_classes; i++) {
        printf("Accuracy %f class %i num instances %i\n", 1.0 * accuracy[i] / evaluated[i], i,
               evaluated[i]);
    }

    printf("Accuracy total %f evaluates samples %i of %i\n", 1.0 * accuracy_total / read_samples,
           evaluated_total, read_samples);
}

void find_n_classes(struct feature features[MAX_TEST_SAMPLES], int *n_classes, int read_samples)
{

    *n_classes = features[0].prediction;

    for (int i = 1; i < read_samples; i++) {
        if (*n_classes < features[i].prediction) { *n_classes = features[i].prediction; }
    }
}

void get_mismatchs(uint8_t *predictions_hw, uint8_t *predictions_sw, int read_samples)
{

    int mismatchs = 0;

    for (int i = 0; i < read_samples; i++){
        if (predictions_hw[i] != predictions_sw[i]){
            mismatchs++;
            printf("Error %i predictions_hw,%i != predictions_sw,%i\n", i, predictions_hw[i], predictions_sw[i]);
        }
    }

    printf("Num mismatch %i\n", mismatchs);
}

int main(int argc, char **argv)
{
    token_t *features_buf[MAX_TEST_SAMPLES/MAX_BURST];
    token_t *tree_buf;
    struct feature features_read[MAX_TEST_SAMPLES];
    uint8_t predictions_sw[MAX_TEST_SAMPLES];
    uint8_t predictions_hw[MAX_TEST_SAMPLES];
    int n_classes;
    int read_samples;
    float exe_time_ms_hw;
    float exe_time_ms_sw;

    init_parameters();
    for (int i = 0; i < MAX_TEST_SAMPLES/MAX_BURST; i++)
        features_buf[i] = (token_t *)esp_alloc(MAX_BURST*N_FEATURE*(sizeof(float)));
    tree_buf = (token_t *)esp_alloc(size);

    // Validación de los argumentos: se esperan dos argumentos (dataset y modelo)
    if (argc < 3) {
        printf("Use: %s <dataset.csv> <modelo.model>\n", argv[0]);
        return 1;
    }

    printf("\nExecute ====== %s 2.0 ======\n\n", cfg_000[0].devname);

    // Cargar dataset desde el archivo recibido por línea de comandos
    printf("Cargando features desde %s...\n", argv[1]);
    read_samples = read_n_features(argv[1], MAX_TEST_SAMPLES, features_read, features_buf);
    if (read_samples < 0) {
        return 1;
    }

    find_n_classes(features_read, &n_classes, read_samples);
    printf("Num clases of the dataset %i\n", n_classes);
    printf("Num features_read from the dataset %i\n", read_samples);

    // Cargar modelo desde el archivo recibido por línea de comandos
    printf("Cargando modelo desde %s...\n", argv[2]);
    load_model(tree_buf, argv[2]);
    
    printf("evaluate_model software\n");
    software_prediction(features_read, read_samples, tree_buf, n_classes, predictions_sw, &exe_time_ms_sw);

    printf("evaluate_model hardware\n");
    evaluate_model(tree_buf, features_buf, features_read, read_samples,
                    n_classes, predictions_hw, MAX_BURST, &exe_time_ms_hw);

    printf("Speed up hardware vs software %f\n", exe_time_ms_sw/exe_time_ms_hw);

    get_mismatchs(predictions_hw, predictions_sw, read_samples);

    for (int i = 0; i < MAX_TEST_SAMPLES/MAX_BURST; i++)
        esp_free(features_buf[i]);

    esp_free(tree_buf);

    return 0;
}
