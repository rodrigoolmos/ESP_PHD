// Copyright (c) 2011-2024 Columbia University, System Level Design Group
// SPDX-License-Identifier: Apache-2.0
#include "libesp.h"
#include "cfg.h"

static unsigned in_words_adj;
static unsigned out_words_adj;
static unsigned in_len;
static unsigned out_len;
static unsigned in_size;
static unsigned out_size;
static unsigned out_offset;
static unsigned size;

/* User-defined code */
static int validate_buffer(token_t *out, token_t *gold)
{
    int i;
    int j;
    unsigned errors = 0;

    for (i = 0; i < 1; i++)
        for (j = 0; j < 15; j++)
            if (gold[i * out_words_adj + j] != out[i * out_words_adj + j]){
                errors++;
                printf("Error in %i != %i", gold[i * out_words_adj + j], out[i * out_words_adj + j]);
            }

    return errors;
}

/* User-defined code */
static void init_buffer(token_t *in, token_t *gold)
{
    int i;
    int j;

    for (i = 0; i < 1; i++)
        for (j = 0; j < 15; j++)
            in[i * in_words_adj + j] = (token_t)j;

    for (i = 0; i < 1; i++)
        for (j = 0; j < 15; j++)
            gold[i * out_words_adj + j] = (token_t)j + 100;
}

/* User-defined code */
static void init_parameters()
{
    if (DMA_WORD_PER_BEAT(sizeof(token_t)) == 0) {
        in_words_adj  = reg0;
        out_words_adj = reg0;
    }
    else {
        in_words_adj  = round_up(reg0, DMA_WORD_PER_BEAT(sizeof(token_t)));
        out_words_adj = round_up(reg0, DMA_WORD_PER_BEAT(sizeof(token_t)));
    }
    in_len     = in_words_adj * (1);
    out_len    = out_words_adj * (1);
    in_size    = in_len * sizeof(token_t);
    out_size   = out_len * sizeof(token_t);
    out_offset = 33;
    size       = (out_offset * sizeof(token_t)) + out_size;
}

int main(int argc, char **argv)
{
    int errors;

    token_t *gold;
    token_t *buf;

    init_parameters();

    buf               = (token_t *)esp_alloc(size);
    cfg_000[0].hw_buf = buf;

    gold = malloc(out_size);

    init_buffer(buf, gold);

    printf("\n====== %s ======\n\n", cfg_000[0].devname);
    /* <<--print-params-->> */
	printf("  .reg1 = %d\n", reg1);
	printf("  .reg0 = %d\n", reg0);
    printf("\n  ** START **\n");

    esp_run(cfg_000, NACC);

    printf("\n  ** DONE **\n");

    errors = validate_buffer(&buf[out_offset], gold);

    for (int i = 0; i < 15; i++){
        printf("Gold %i\n", gold[i]);
        printf("Buf %i\n", buf[out_offset+i]);
    }
    

    free(gold);
    esp_free(buf);

    if (!errors) 
        printf("+ Test PASSED\n");
    else
        printf("  ... FAIL num errors %d\n", errors);

    printf("\n====== %s ======\n\n", cfg_000[0].devname);

    return errors;
}
