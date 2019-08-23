/* SPDX-License-Identifier: BSD-3-Clause */

#include <stdlib.h>

#include "tpm2.h"
#include "log.h"
#include "tpm2_tool.h"

typedef struct transient_object {
    const char *ctx_path;
    tpm2_loaded_object object;
} transient_object_t;

/*
 * Structure to hold ctx for this tool.
 */
typedef struct getname_opts {
    transient_object_t tr_object;
} getname_opts_t;

static getname_opts_t ctx;


static bool on_option(char key, char *value) {

    UNUSED(key);
    UNUSED(value);

    switch (key) {
    case 'c':
        ctx.tr_object.ctx_path = value;
        break;
    }

    return true;
}

static bool on_args(int argc, char **argv) {

    UNUSED(argv);

    if (argc > 0) {
        LOG_ERR("Please do not specify any argument besides -c <object context>");
        return false;
    }

    return true;
}

bool tpm2_tool_onstart(tpm2_options **opts) {

    static struct option topts[] = {
        { "key-context", required_argument, NULL, 'c' },
    };

    *opts = tpm2_options_new("c:", ARRAY_LEN(topts), topts, on_option, on_args,
                             0);

    return *opts != NULL;
}

tool_rc tpm2_tool_onrun(ESYS_CONTEXT *ectx, tpm2_option_flags flags) {

    UNUSED(flags);

    TPM2_RC rc;
    TPM2B_NAME *name = NULL;

    if (!ctx.tr_object.ctx_path) {
        LOG_ERR("Expected argument -c.");
        return tool_rc_option_error;
    }

    rc = tpm2_util_object_load(ectx, ctx.tr_object.ctx_path,
                               &ctx.tr_object.object,
                               TPM2_HANDLE_ALL_W_NV);

    if (rc != tool_rc_success) {
        LOG_ERR("Could not load context %s", ctx.tr_object.ctx_path);
        goto out;
    }

    rc = tpm2_tr_get_name(ectx, (ESYS_TR) ctx.tr_object.object.tr_handle, &name);
    if (rc != tool_rc_success) {
        LOG_ERR("Could not get name from saveHandle 0x%x",
                ctx.tr_object.object.tr_handle);
        goto out;
    }

    tpm2_tool_output("name: ");
    tpm2_util_hexdump(name->name, name->size);
    tpm2_tool_output("\n");

    rc = tool_rc_success;

out:
    free(name);
    return rc;
}
