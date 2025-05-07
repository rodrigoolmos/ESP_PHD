// Copyright (c) 2011-2024 Columbia University, System Level Design Group
// SPDX-License-Identifier: Apache-2.0
#include <linux/of_device.h>
#include <linux/mm.h>

#include <asm/io.h>

#include <esp_accelerator.h>
#include <esp.h>

#include "test_rtl.h"

#define DRV_NAME "test_rtl"

/* <<--regs-->> */
#define TEST_REG1_REG 0x44
#define TEST_REG0_REG 0x40

struct test_rtl_device {
    struct esp_device esp;
};

static struct esp_driver test_driver;

static struct of_device_id test_device_ids[] = {
    {
        .name = "SLD_TEST_RTL",
    },
    {
        .name = "eb_88",
    },
    {
        .compatible = "sld,test_rtl",
    },
    {},
};

static int test_devs;

static inline struct test_rtl_device *to_test(struct esp_device *esp)
{
    return container_of(esp, struct test_rtl_device, esp);
}

static void test_prep_xfer(struct esp_device *esp, void *arg)
{
    struct test_rtl_access *a = arg;

    /* <<--regs-config-->> */
	iowrite32be(a->reg1, esp->iomem + TEST_REG1_REG);
	iowrite32be(a->reg0, esp->iomem + TEST_REG0_REG);
    iowrite32be(a->src_offset, esp->iomem + SRC_OFFSET_REG);
    iowrite32be(a->dst_offset, esp->iomem + DST_OFFSET_REG);
}

static bool test_xfer_input_ok(struct esp_device *esp, void *arg)
{
    /* struct test_rtl_device *test = to_test(esp); */
    /* struct test_rtl_access *a = arg; */

    return true;
}

static int test_probe(struct platform_device *pdev)
{
    struct test_rtl_device *test;
    struct esp_device *esp;
    int rc;

    test = kzalloc(sizeof(*test), GFP_KERNEL);
    if (test == NULL) return -ENOMEM;
    esp         = &test->esp;
    esp->module = THIS_MODULE;
    esp->number = test_devs;
    esp->driver = &test_driver;
    rc          = esp_device_register(esp, pdev);
    if (rc) goto err;

    test_devs++;
    return 0;
err:
    kfree(test);
    return rc;
}

static int __exit test_remove(struct platform_device *pdev)
{
    struct esp_device *esp                        = platform_get_drvdata(pdev);
    struct test_rtl_device *test = to_test(esp);

    esp_device_unregister(esp);
    kfree(test);
    return 0;
}

static struct esp_driver test_driver = {
    .plat =
        {
            .probe  = test_probe,
            .remove = test_remove,
            .driver =
                {
                    .name           = DRV_NAME,
                    .owner          = THIS_MODULE,
                    .of_match_table = test_device_ids,
                },
        },
    .xfer_input_ok = test_xfer_input_ok,
    .prep_xfer     = test_prep_xfer,
    .ioctl_cm      = TEST_RTL_IOC_ACCESS,
    .arg_size      = sizeof(struct test_rtl_access),
};

static int __init test_init(void)
{
    return esp_driver_register(&test_driver);
}

static void __exit test_exit(void) { esp_driver_unregister(&test_driver); }

module_init(test_init) module_exit(test_exit)

    MODULE_DEVICE_TABLE(of, test_device_ids);

MODULE_AUTHOR("Emilio G. Cota <cota@braap.org>");
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("test_rtl driver");
