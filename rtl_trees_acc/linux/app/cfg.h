// Copyright (c) 2011-2024 Columbia University, System Level Design Group
// SPDX-License-Identifier: Apache-2.0
#ifndef __ESP_CFG_000_H__
#define __ESP_CFG_000_H__

#include "libesp.h"
#include "trees_rtl.h"

typedef int64_t token_t;

/* <<--params-def-->> */
#define BURST_LEN 128
#define LOAD_TREES 0

/* <<--params-->> */
const int32_t burst_len = BURST_LEN;
const int32_t load_trees = LOAD_TREES;

#define NACC 1

struct trees_rtl_access trees_cfg_000[] = {{
    /* <<--descriptor-->> */
		.burst_len = BURST_LEN,
		.load_trees = LOAD_TREES,
    .src_offset    = 0,
    .dst_offset    = 0,
    .esp.coherence = ACC_COH_NONE,
    .esp.p2p_store = 0,
    .esp.p2p_nsrcs = 0,
    .esp.p2p_srcs  = {"", "", "", ""},
}};

esp_thread_info_t cfg_000[] = {{
    .run       = true,
    .devname   = "trees_rtl.0",
    .ioctl_req = TREES_RTL_IOC_ACCESS,
    .esp_desc  = &(trees_cfg_000[0].esp),
}};


///////////////////////////////////////////////////////////////////////////////////

#define N_NODE_AND_LEAFS 256    // Adjust according to the maximum number of nodes and leaves in your trees
#define N_TREES 128             // Adjust according to the number of trees in your model
#define N_FEATURE 32            // Adjust according to the number of features in your model
#define MAX_TEST_SAMPLES 30000  // Adjust according to the maximum number of test samples
#define MAX_LINE_LENGTH 1024    // Adjust according to the maximum line length in your CSV file
#define N_CLASSES 32            // Adjust according to the number of classes in your model
#define MAX_BURST 5000          // Adjust according to the maximum amount of somples to process in 1 busrt



typedef union {
  float f;
  int32_t i;
} float_int_union_t;

struct tree_camps {
  uint8_t leaf_or_node;
  uint8_t feature_index;
  uint8_t next_node_right_index;
  uint8_t padding;
  float_int_union_t float_int_union;
};

typedef union {
  struct tree_camps tree_camps;
  uint64_t compact_data;
} tree_data;

struct feature {
  float features[N_FEATURE];
  uint8_t prediction;
};


#endif /* __ESP_CFG_000_H__ */
