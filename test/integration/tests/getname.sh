# SPDX-License-Identifier: BSD-3-Clause

source helpers.sh

handle_persistent=0x81010000
nv_index=0x01500016
owner_pass=123456

cleanup() {
  rm -f sym.key key.ctx primary.ctx key.pub key.priv \
        name_1.bin name_1.yml name_2.yml name_3.yml name_4.yml

  if [ $(ina "$@" "keep_handle") -ne 0 ]; then
    tpm2_evictcontrol -Q -Co -c $handle_persistent 2>/dev/null || true
  fi

  if [ $(ina "$@" "keep_owner_auth") -ne 0 ]; then
    tpm2_changeauth -Q -c o -p $owner_pass 2>/dev/null || true
  fi

  if [ $(ina "$@" "keep_nvindex") -ne 0 ]; then
    tpm2_nvundefine -Q $nv_index 2>/dev/null || true
  fi

  if [ $(ina "$@" "no-shut-down") -ne 0 ]; then
    shut_down
  fi
}
trap cleanup EXIT

start_up

cleanup "no-shut-down"

tpm2_clear

# loadexternal aes
dd if=/dev/urandom of=sym.key bs=1 count=$((128 / 8)) 2>/dev/null
tpm2_loadexternal -G aes -r sym.key -c key.ctx > name_1.yml
tpm2_getname -c key.ctx > name_2.yml
diff name_1.yml name_2.yml

# load rsa
tpm2_createprimary -Q -C e -g sha1 -G rsa -c primary.ctx
tpm2_create -Q -g sha256 -G rsa -u key.pub -r key.priv -C primary.ctx
tpm2_load -Q -C primary.ctx -u key.pub -r key.priv -n name_1.bin -c key.ctx
echo "name: $(cat name_1.bin | xxd -c 256 -p)" > name_1.yml
tpm2_getname -c key.ctx > name_2.yml

# persistent handle with auth
tpm2_changeauth -c o $owner_pass
tpm2_evictcontrol -C o -c key.ctx $handle_persistent -P $owner_pass
tpm2_getname -c $handle_persistent > name_3.yml
diff name_1.yml name_2.yml
diff name_2.yml name_3.yml

cleanup "no-shut-down"

# nv
tpm2_nvdefine $nv_index -C o -s 32 -a "ownerread|ownerwrite|policywrite"
tpm2_getname -c $nv_index > name_1.yml
# unfortunately there is no way to double-check name
tpm2_nvundefine $nv_index

cleanup "no-shut-down"

# hierarchy
tpm2_getname -c "o" > name_1.yml
tpm2_getname -c "owner" > name_2.yml
tpm2_getname -c "0x40000001" > name_3.yml
echo "name: 40000001" > name_4.yml
diff name_1.yml name_2.yml
diff name_2.yml name_3.yml
diff name_3.yml name_4.yml

cleanup "no-shut-down"

exit 0
