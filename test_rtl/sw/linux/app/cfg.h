// Copyright (c) 2011-2024 Columbia University, System Level Design Group
// SPDX-License-Identifier: Apache-2.0
#ifndef __ESP_CFG_000_H__
#define __ESP_CFG_000_H__

#include "libesp.h"
#include "test_rtl.h"

typedef int64_t token_t;

/* <<--params-def-->> */
#define REG1 456
#define REG0 123

/* <<--params-->> */
const int32_t reg1 = REG1;
const int32_t reg0 = REG0;

#define NACC 1

struct test_rtl_access test_cfg_000[] = {{
    /* <<--descriptor-->> */
		.reg1 = REG1,
		.reg0 = REG0,
    .src_offset    = 0,
    .dst_offset    = 0,
    .esp.coherence = ACC_COH_NONE,
    .esp.p2p_store = 0,
    .esp.p2p_nsrcs = 0,
    .esp.p2p_srcs  = {"", "", "", ""},
}};

esp_thread_info_t cfg_000[] = {{
    .run       = true,
    .devname   = "test_rtl.0",
    .ioctl_req = TEST_RTL_IOC_ACCESS,
    .esp_desc  = &(test_cfg_000[0].esp),
}};

#endif /* __ESP_CFG_000_H__ */
