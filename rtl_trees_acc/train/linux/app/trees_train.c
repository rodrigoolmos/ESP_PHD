// Copyright (c) 2011-2024 Columbia University, System Level Design Group
// SPDX-License-Identifier: Apache-2.0
#include "libesp.h"
#include "cfg.h"
#include "monitors.h"
#include "train.h"

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


int read_n_features(const char *csv_file, int n, struct feature *features, int *n_col) {
    FILE *file = fopen(csv_file, "r");
    char line[MAX_LINE_LENGTH];
    int features_read = 0;
    int i;

    if (!file) {
        perror("Failed to open the file");
        return -1;
    }

    while (fgets(line, MAX_LINE_LENGTH, file) && features_read < n) {
        float temp[N_FEATURE + 1];
        char *token = strtok(line, ",");
        *n_col = 0;

        while (token != NULL && (*n_col) < N_FEATURE + 1) {
            temp[*n_col] = atof(token);
            token = strtok(NULL, ",");
            (*n_col)++;
        }

        for (i = 0; i < *n_col - 1; i++) {
            features[features_read].features[i] = temp[i];
        }
        features[features_read].prediction = (uint8_t) temp[*n_col - 1];

        features_read++;
    }

    fclose(file);
    return features_read;
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

void coppy_trees(tree_data tree[N_TREES][N_NODE_AND_LEAFS], token_t *buf)
{
    for (int t = 0; t < N_TREES; t++) {
        for (int n = 0; n < N_NODE_AND_LEAFS; n++) {
            buf[t * N_NODE_AND_LEAFS + n] = tree[t][n].compact_data;
        }
    }
}

void copy_features_bytes(token_t *mem, const struct feature *features, int n_features)
{
    uint8_t *dst_bytes = (uint8_t *)mem;

    for (int i = 0; i < n_features; i++) {
        size_t offset = i * sizeof(float)*N_FEATURE;
        memcpy(dst_bytes + offset, features[i].features, sizeof(float)*N_FEATURE);
    }
}

void send_trees(token_t *buf)
{
    
    trees_cfg_000[0].burst_len = 0;
    trees_cfg_000[0].load_trees = 1;
    cfg_000[0].hw_buf = buf;
    esp_run(cfg_000, NACC);

}

void perform_inferences_hw(token_t *buf, struct feature *features, int read_samples,
                           uint8_t *predictions, float *exe_time_ms, uint8_t new_features)
{

    if (new_features){
        trees_cfg_000[0].burst_len = read_samples;
        trees_cfg_000[0].load_trees = 0;
        copy_features_bytes(buf, features, read_samples);
    }else{
        trees_cfg_000[0].burst_len = 0;
        trees_cfg_000[0].load_trees = 0;
    }
    
    cfg_000[0].hw_buf = buf;
    esp_run(cfg_000, NACC);
    
    memcpy(predictions, buf, read_samples);

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

void evaluate_model(token_t *buf, struct feature *features, int read_samples, int n_classes,
                    uint8_t *predictions, uint32_t max_burst, float *exe_time_ms, uint8_t new_features)
{
    uint32_t processed = 0;
    uint32_t burst;
    float exe_t;
    *exe_time_ms = 0;

    send_trees(buf);

    while (processed < read_samples) {
        burst =
            (read_samples - processed) > max_burst ? max_burst : (read_samples - processed);
        printf("Processing batch %i, processed %i of %i\n", burst, processed, read_samples);
        perform_inferences_hw(buf, &features[processed], 
                                burst, &predictions[processed], &exe_t, new_features);
    
        *exe_time_ms += exe_t;
        processed += burst;
    }

    print_accuracy(features, predictions, read_samples, n_classes);
}

void get_accuracy(struct feature *features, int read_samples, uint8_t *prediction, float *accuracy){

    int correct = 0;

    for (int s = 0; s < read_samples; s++){
        if (features[s].prediction == prediction[s]){
            correct++;
        }
    }
    
    *accuracy = (float) correct / (float) read_samples;

}

void print_tree(tree_data trees[N_TREES][N_NODE_AND_LEAFS]){

    for (int t = 0; t < N_TREES; t++){
        printf("Tree %i\n", t);
        for (int n = 0; n < N_NODE_AND_LEAFS; n++){
            printf("  >>  Tree %i node %i feature_index %i\n", t, n, trees[t][n].tree_camps.feature_index);
            if (trees[t][n].tree_camps.leaf_or_node == 0)
                printf("  >>  Tree %i node %i leaf val %i\n", t, n, trees[t][n].tree_camps.float_int_union.i);
            else            
                printf("  >>  Tree %i node %i node val %f\n", t, n, trees[t][n].tree_camps.float_int_union.f);
            printf("  >>  Tree %i node %i node index %i\n", t, n, trees[t][n].tree_camps.next_node_right_index);
        }
    }
    

}

void train_model(tree_data trees_population[POPULATION][N_TREES][N_NODE_AND_LEAFS], 
                    token_t *buf, struct feature *features, int read_samples, 
                    float *accuracy, uint8_t sow_log, int32_t *trees_used, int n_classes){

    uint32_t processed;
    uint32_t burst;
    float exe_t;
    uint8_t predictions[MAX_TEST_SAMPLES];

    u_int8_t load_features = TRUE;

    
    for (int p = 0; p < POPULATION; p++){

        processed = 0;
        
        //print_tree(trees_population[p]);
        coppy_trees(trees_population[p], buf);
        send_trees(buf);

        while (processed < read_samples) {
            burst =
                (read_samples - processed) > MAX_BURST ? MAX_BURST : (read_samples - processed);
            perform_inferences_hw(buf, &features[processed], 
                                    burst, &predictions[processed], &exe_t, load_features);
        
            processed += burst;
            load_features = FALSE;
        }

        get_accuracy(features, read_samples, predictions, &accuracy[p]);

    }

}

void export_model(tree_data trees[N_TREES][N_NODE_AND_LEAFS], const char* filename) {
    FILE* f = fopen(filename, "wb");
    if (!f) {
        perror("Failed to open model file");
        return;
    }

    // Write header
    fwrite("model", 1, 5, f);

    for (int t = 0; t < N_TREES; ++t) {
        for (int i = 0; i < N_NODE_AND_LEAFS; ++i) {
            int64_t compact_data = trees[t][i].compact_data;

            fwrite(&compact_data, sizeof(int64_t), 1, f);
        }
    }

    fclose(f);
}

void show_logs(float population_accuracy[POPULATION]){

    for (int32_t p = 0; p < 10; p++){
        printf("RANKING %i -> %f \n", p, population_accuracy[p]);
    }
}

int main(int argc, char **argv)
{
    token_t *buf;
    uint8_t predictions[MAX_TEST_SAMPLES];
    int n_classes;
    int n_features;
    int read_samples;
    float exe_time_ms_hw;
    struct timespec startn, endn;
    unsigned long long sw_ns;

    float population_accuracy[POPULATION] = {0};
    float iteration_accuracy[MEMORY_ACU_SIZE] = {0};
    float mutation_factor = 0;
    float max_features[N_FEATURE] = {0};
    float min_features[N_FEATURE] = {0};
    float class_100x100[256] = {0};

    struct feature features[MAX_TEST_SAMPLES];
    struct feature features_augmented[MAX_TEST_SAMPLES*10];
    int ite_no_impru = 0;
    uint32_t used_trees = 0;
    uint32_t used_trees_test = 0;
    int generation_ite = 0;

    tree_data trees_population[POPULATION][N_TREES][N_NODE_AND_LEAFS] = {0};
    tree_data golden_tree[N_TREES][N_NODE_AND_LEAFS] = {0};

    for (int p = 0; p < POPULATION; p++)
        initialize_trees(trees_population[p]);
        
    initialize_trees(golden_tree);

    srand(clock());

    // Validación de los argumentos: se esperan dos argumentos (dataset y modelo)
    if (argc < 2) {
        printf("Train use : %s <dataset.csv> \n", argv[0]);
        return 1;
    }

    printf("\nTrain mode 1 ====== %s ======\n\n", cfg_000[0].devname);

    // Cargar dataset desde el archivo recibido por línea de comandos
    printf("Cargando features desde %s...\n", argv[1]);
    read_samples = read_n_features(argv[1], MAX_TEST_SAMPLES, features, &n_features);
    n_features--; // remove predictions
    if (read_samples < 0) {
        return 1;
    }

    find_max_min_features(features, max_features, min_features, read_samples);
    find_n_classes(features, &n_classes, read_samples);
    printf("Num clases of the dataset %i\n", n_classes);
    printf("Num features_read from the dataset %i\n", read_samples);
    printf("Num n_features from the dataset %i\n", n_features);

    read_samples = augment_features(features, read_samples, n_features, 
                                    max_features, min_features, features_augmented,
                                    MAX_TEST_SAMPLES*10, 0);

    read_samples /= 10; // reduce the amount of samples

    init_parameters();

    buf = (token_t *)esp_alloc(size);

    for (size_t boosting_i = 0; boosting_i < N_TREES / N_BOOSTING; boosting_i++){
        used_trees = (boosting_i + 1)*N_BOOSTING;
        generation_ite = 0;
        shuffle(features_augmented, read_samples);

        for (uint32_t p = 0; p < POPULATION; p++)
            generate_random_trees(trees_population[p], n_features, boosting_i,
                                    max_features, min_features, n_classes);

        while(1){
            gettime(&startn);
            train_model(trees_population, buf, features_augmented, 
                            read_samples * 80/100, population_accuracy, 
                            0, &used_trees, n_classes);
            gettime(&endn);
            sw_ns = ts_subtract(&startn, &endn);
            printf("Infe\t\t time: %f s\n", sw_ns/1000000000.0);
        
            gettime(&startn);
            reorganize_population(population_accuracy, trees_population, used_trees);
            gettime(&endn);
            sw_ns = ts_subtract(&startn, &endn);
            printf("reorganize\t time: %f s\n", sw_ns/1000000000.0);

            /////////////////////////////// tests ///////////////////////////////
            show_logs(population_accuracy);
            // evaluation features from out the training dataset
            printf("Boosting iteration %i of %i\n", boosting_i, N_TREES / N_BOOSTING);
            used_trees_test = used_trees - N_BOOSTING; // number of trees used on the previous iteration
            if (used_trees_test > 0){
                coppy_trees(golden_tree, buf);
                evaluate_model(buf, features_augmented, read_samples, n_classes, 
                                        predictions, MAX_BURST, &exe_time_ms_hw, FALSE);
            }
            /////////////////////////////////////////////////////////////////////
            
            gettime(&startn);
            if(population_accuracy[0] >= 1 || ite_no_impru > MAX_NO_IMPRU){
                ite_no_impru = 0;
                shuffle(features_augmented, read_samples* 80/100);
                for (int accuracy_i = 0; accuracy_i < MEMORY_ACU_SIZE; accuracy_i++){
                    iteration_accuracy[accuracy_i] = 0;
                }
                break;
            }

            mutate_population(trees_population, population_accuracy, max_features,
                                min_features, n_features, mutation_factor, boosting_i, n_classes,
                                class_100x100);

            crossover(trees_population, boosting_i);

            generation_ite ++;
            mutation_factor = 0;
            iteration_accuracy[generation_ite % MEMORY_ACU_SIZE] = population_accuracy[0];
            for (int accuracy_i = 0; accuracy_i < MEMORY_ACU_SIZE; accuracy_i++){
                if(iteration_accuracy[generation_ite % MEMORY_ACU_SIZE] <= iteration_accuracy[accuracy_i]){
                    if ((generation_ite % MEMORY_ACU_SIZE) != accuracy_i){
                        mutation_factor += 0.02;
                    }
                }
            }

            if (mutation_factor >= (MEMORY_ACU_SIZE - 2)*0.02){
                ite_no_impru++;
            }else{
                ite_no_impru = 0;
            }
            
            printf("Mutation_factor %f ite_no_impru = %i\n", mutation_factor, ite_no_impru);
            printf("Generation ite %i index ite %i\n", generation_ite, generation_ite % MEMORY_ACU_SIZE);
            gettime(&endn);
            sw_ns = ts_subtract(&startn, &endn);
            printf("Rest\t\t time: %f s\n", sw_ns/1000000000.0);
        }

        // coppy the amount of trees trained up to this point
        for (uint32_t tree_i = 0; tree_i < used_trees; tree_i++){
            memcpy(golden_tree[tree_i], trees_population[0][tree_i], sizeof(tree_data) * N_NODE_AND_LEAFS);
        }
        for (uint32_t p = 1; p < POPULATION; p++){
            for (uint32_t tree_i = 0; tree_i < N_TREES; tree_i++){
                memcpy(trees_population[p][tree_i], trees_population[0][tree_i], sizeof(tree_data) * N_NODE_AND_LEAFS);
            }
        }
    }

    printf("Final evaluation !!!!\n\n");
    coppy_trees(golden_tree, buf);
    evaluate_model(buf, features_augmented, read_samples, n_classes, 
        predictions, MAX_BURST, &exe_time_ms_hw, TRUE);

    printf("Exporting model\n");
    export_model(golden_tree, "model.bin");

    esp_free(buf);

    return 0;
}