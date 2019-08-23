% tpm2_getname(1) tpm2-tools | General Commands Manual

# NAME

**tpm2_getname**(1) - Retrieve the name of a TPM entity by its handle or key
context.

# SYNOPSIS

**tpm2_getname** [*OPTIONS*]

# DESCRIPTION

**tpm2_getname**(1) - Retrieve the name of a TPM entity by its handle or key
context. The entity can be an HMAC session, policy session, permanent value,
NV index, transient object or persistent object. Note that for all entities
which are not transient or persistent objects, the entity's name will be equal
to its handle. PCR handles are not supported.

# OPTIONS

  * **-c**, **\--key-context**=_OBJECT\_CONTEXT\_FILE_:

    Context object of the entity whose name will be returned. Either a file or a
    handle number.
    See section "Context Object Format".

[common options](common/options.md)

[context object format](common/ctxobj.md)

[common tcti options](common/tcti.md)

# EXAMPLES

## Key Objects

To get the name of a transient object:

```bash
tpm2_createprimary -C o -c key.ctx
tpm2_getname key.ctx
```

To get the name of a persistent object:

```bash
tpm2_createprimary -C o -c key.ctx
tpm2_evictcontrol -C o -c key.ctx 0x81010000
tpm2_getname -c key.ctx
```

Alternatively, the handle can be used:

```bash
tpm2_getname -c 0x81010000
```

## NV Indices

To get the name of a NV index:

```bash
tpm2_nvdefine -C o -a "ownerread|ownerwrite|policywrite" 0x01500016
tpm2_getname -c 0x01500016
```

[returns](common/returns.md)

[footer](common/footer.md)
