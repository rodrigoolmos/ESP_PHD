/* Copyright (c) 2011-2024 Columbia University, System Level Design Group */
/* SPDX-License-Identifier: Apache-2.0 */

#include <stdio.h>
#ifndef __riscv
    #include <stdlib.h>
#endif

#include <esp_accelerator.h>
#include <esp_probe.h>
#include <fixed_point.h>

typedef int64_t token_t;

static unsigned DMA_WORD_PER_BEAT(unsigned _st) { return (sizeof(void *) / _st); }

#define SLD_TEST 0x88
#define DEV_NAME             "sld,test_rtl"

/* <<--params-->> */
const int32_t reg1 = 456;
const int32_t reg0 = 123;

static unsigned in_words_adj;
static unsigned out_words_adj;
static unsigned in_len;
static unsigned out_len;
static unsigned in_size;
static unsigned out_size;
static unsigned out_offset;
static unsigned mem_size;

/* Size of the contiguous chunks for scatter/gather */
#define CHUNK_SHIFT 20
#define CHUNK_SIZE  BIT(CHUNK_SHIFT)
#define NCHUNK(_sz) ((_sz % CHUNK_SIZE == 0) ? (_sz / CHUNK_SIZE) : (_sz / CHUNK_SIZE) + 1)

/* User defined registers */
/* <<--regs-->> */
#define TEST_REG1_REG 0x44
#define TEST_REG0_REG 0x40

static int validate_buf(token_t *out, token_t *gold)
{
    int i;
    int j;
    unsigned errors = 0;

    for (i = 0; i < 1; i++)
        for (j = 0; j < 15; j++)
            if (gold[i * out_words_adj + j] != out[i * out_words_adj + j]){
                errors++;
                printf("Error in %d != %d", gold[i * out_words_adj + j], out[i * out_words_adj + j])
            }

    return errors;
}

static void init_buf(token_t *in, token_t *gold)
{
    int i;
    int j;

    for (i = 0; i < 1; i++)
        for (j = 0; j < reg0; j++)
            in[i * in_words_adj + j] = (token_t)j;

    for (i = 0; i < 1; i++)
        for (j = 0; j < reg0; j++)
            gold[i * out_words_adj + j] = (token_t)j + 100;
}

int main(int argc, char *argv[])
{
    int i;
    int n;
    int ndev;
    struct esp_device *espdevs;
    struct esp_device *dev;
    unsigned done;
    unsigned **ptable;
    token_t *mem;
    token_t *gold;
    unsigned errors = 0;
    unsigned coherence;

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
    mem_size   = (out_offset * sizeof(token_t)) + out_size;

    // Search for the device
    printf("Scanning device tree... \n");

    ndev = probe(&espdevs, VENDOR_SLD, SLD_TEST, DEV_NAME);
    if (ndev == 0) {
        printf("test not found\n");
        return 0;
    }

    for (n = 0; n < ndev; n++) {

        printf("**************** %s.%d ****************\n", DEV_NAME, n);

        dev = &espdevs[n];

        // Check DMA capabilities
        if (ioread32(dev, PT_NCHUNK_MAX_REG) == 0) {
            printf("  -> scatter-gather DMA is disabled. Abort.\n");
            return 0;
        }

        if (ioread32(dev, PT_NCHUNK_MAX_REG) < NCHUNK(mem_size)) {
            printf("  -> Not enough TLB entries available. Abort.\n");
            return 0;
        }

        // Allocate memory
        gold = aligned_malloc(out_size);
        mem  = aligned_malloc(mem_size);
        printf("  memory buffer base-address = %p\n", mem);

        // Alocate and populate page table
        ptable = aligned_malloc(NCHUNK(mem_size) * sizeof(unsigned *));
        for (i = 0; i < NCHUNK(mem_size); i++)
            ptable[i] = (unsigned *)&mem[i * (CHUNK_SIZE / sizeof(token_t))];

        printf("  ptable = %p\n", ptable);
        printf("  nchunk = %lu\n", NCHUNK(mem_size));

        for (coherence = ACC_COH_NONE; coherence <= ACC_COH_RECALL; coherence++) {
            printf("  --------------------\n");
            printf("  Generate input...\n");
            init_buf(mem, gold);

            // Pass common configuration parameters
            iowrite32(dev, COHERENCE_REG, coherence);

#ifndef __sparc
            iowrite32(dev, PT_ADDRESS_REG, (unsigned long long)ptable);
#else
            iowrite32(dev, PT_ADDRESS_REG, (unsigned)ptable);
#endif
            iowrite32(dev, PT_NCHUNK_REG, NCHUNK(mem_size));
            iowrite32(dev, PT_SHIFT_REG, CHUNK_SHIFT);

            // Use the following if input and output data are not allocated at the default offsets
            iowrite32(dev, SRC_OFFSET_REG, 0x0);
            iowrite32(dev, DST_OFFSET_REG, 0x0);

            // Pass accelerator-specific configuration parameters
            /* <<--regs-config-->> */
			iowrite32(dev, TEST_REG1_REG, reg1);
			iowrite32(dev, TEST_REG0_REG, reg0);

            // Flush (customize coherence model here)
            esp_flush(coherence);

            // Start accelerators
            printf("  Start...\n");
            iowrite32(dev, CMD_REG, CMD_MASK_START);

            // Wait for completion
            done = 0;
            while (!done) {
                done = ioread32(dev, STATUS_REG);
                done &= STATUS_MASK_DONE;
            }
            iowrite32(dev, CMD_REG, 0x0);

            printf("  Done\n");
            printf("  validating...64-32\n");

            for (int i = 0; i < 15; i++){
                printf("Gold %d\n", gold[i]);
                printf("Buf %d\n", mem[out_offset+i]);
            }

            /* Validation */
            errors = validate_buf(&mem[out_offset], gold);
            if (errors) printf("  ... FAIL num errors %d\n", errors);
            else
                printf("  ... PASS\n");
        }
        aligned_free(ptable);
        aligned_free(mem);
        aligned_free(gold);
    }

    return 0;
}
