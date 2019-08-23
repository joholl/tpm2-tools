# SPDX-License-Identifier: BSD-3-Clause

source helpers.sh

cleanup() {
    rm -f import_key.ctx import_key.name import_key.priv import_key.pub \
    parent.ctx plain.dec.ssl  plain.enc plain.txt sym.key import_rsa_key.pub \
    import_rsa_key.priv import_rsa_key.ctx import_rsa_key.name private.pem \
    public.pem plain.rsa.enc plain.rsa.dec public.pem data.in.raw \
    data.in.digest data.out.signed ticket.out ecc.pub ecc.priv ecc.name \
    ecc.ctx private.ecc.pem public.ecc.pem passfile name.yaml stderr


    if [ "$1" != "no-shut-down" ]; then
          shut_down
    fi
}
trap cleanup EXIT

start_up

run_aes_import_test() {

    dd if=/dev/urandom of=sym.key bs=1 count=$3 2>/dev/null

    #Symmetric Key Import Test
    echo "tpm2_import -Q -G aes -g "$name_alg" -i sym.key -C $1 \
    -u import_key.pub -r import_key.priv"

    #Some TPMs might not be able to import aes256 keys (error 0x000002c4)
    try "tpm2_import -Q -G aes -g "$name_alg" -i sym.key -C $1 -u import_key.pub \
    -r import_key.priv" 2> stderr

    if [ $rc != 0 ]; then
        cat stderr
        if [ -z "$(grep '0x000002c4' stderr)" ]; then
            onerror
        else
            return 0
        fi
    fi

    tpm2_load -Q -C $1 -u import_key.pub -r import_key.priv -n import_key.name \
    -c import_key.ctx

    echo "plaintext" > "plain.txt"

    if [ ! -z "$(tpm2_getcap commands | grep 'encryptdecrypt:')" ]; then
        tpm2_encryptdecrypt -c import_key.ctx -o plain.enc plain.txt

        openssl enc -in plain.enc -out plain.dec.ssl -d -K \
        `xxd -c 256 -p sym.key` -iv 0 -$2

        diff plain.txt plain.dec.ssl
    else
        tpm2_getname -c import_key.ctx > name.yaml

        local name1="$(xxd -c 256 -p import_key.name)"
        local name2=$(yaml_get_kv "name.yaml" "name")

        test "$name1" == "$name2"
    fi

    rm import_key.ctx
}

run_rsa_import_test() {

    #Asymmetric Key Import Test
    openssl genrsa -out private.pem $2
    openssl rsa -in private.pem -pubout > public.pem

    # Test an import without the parent public info data to force a readpublic
    tpm2_import -Q -G rsa -g "$name_alg" -i private.pem -C $1 \
    -u import_rsa_key.pub -r import_rsa_key.priv

    tpm2_load -Q -C $1 -u import_rsa_key.pub -r import_rsa_key.priv \
    -n import_rsa_key.name -c import_rsa_key.ctx

    echo "plaintext" > "plain.txt"

    openssl rsa -in private.pem -out public.pem -outform PEM -pubout
    openssl rsautl -encrypt -inkey public.pem -pubin -in plain.txt \
    -out plain.rsa.enc

    tpm2_rsadecrypt -c import_rsa_key.ctx -o plain.rsa.dec plain.rsa.enc

    diff plain.txt plain.rsa.dec

    # test verifying a sigature with the imported key, ie sign in tpm and
    # verify with openssl
    echo "data to sign" > data.in.raw

    sha256sum data.in.raw | awk '{ print "000000 " $1 }' | xxd -r -c 32 > \
    data.in.digest

    tpm2_sign -Q -c import_rsa_key.ctx -g sha256 -d -f plain \
    -o data.out.signed data.in.digest

    openssl dgst -verify public.pem -keyform pem -sha256 -signature \
    data.out.signed data.in.raw

    # Sign with openssl and verify with TPM
    openssl dgst -sha256 -sign private.pem -out data.out.signed data.in.raw

    # Verify with the TPM
    tpm2_verifysignature -Q -c import_rsa_key.ctx -g sha256 -m data.in.raw \
    -f rsassa -s data.out.signed -t ticket.out

    rm import_rsa_key.ctx
}

run_ecc_import_test() {
    #
    # Test loading an OSSL PEM format ECC key, and verifying a signature
    # external to the TPM
    #

    #
    # Generate a Private and Public ECC pem file
    #
    openssl ecparam -name $2 -genkey -noout -out private.ecc.pem
    openssl ec -in private.ecc.pem -out public.ecc.pem -pubout

    # Generate a hash to sign
    echo "data to sign" > data.in.raw
    sha256sum data.in.raw | awk '{ print "000000 " $1 }' | xxd -r -c 32 > \
    data.in.digest

    tpm2_import -Q -G ecc -g "$name_alg" -i private.ecc.pem -C $1 -u ecc.pub \
    -r ecc.priv

    tpm2_load -Q -C $1 -u ecc.pub -r ecc.priv -n ecc.name -c ecc.ctx

    # Sign in the TPM and verify with OSSL
    tpm2_sign -Q -c ecc.ctx -g sha256 -d -f plain -o data.out.signed \
    data.in.digest
    openssl dgst -verify public.ecc.pem -keyform pem -sha256 \
    -signature data.out.signed data.in.raw

    # Sign with openssl and verify with TPM.
    openssl dgst -sha256 -sign private.ecc.pem -out data.out.signed data.in.raw
    tpm2_verifysignature -Q -c ecc.ctx -g sha256 -m data.in.raw -f ecdsa \
    -s data.out.signed

    rm ecc.ctx
}

run_rsa_import_passin_test() {

    if [ "$3" != "stdin" ]; then
        tpm2_import -Q -G rsa -i "$2" -C "$1" \
            -u "import_rsa_key.pub" -r "import_rsa_key.priv" \
            --passin "$3"
    else
        tpm2_import -Q -G rsa -i "$2" -C "$1" \
            -u "import_rsa_key.pub" -r "import_rsa_key.priv" \
            --passin "$3" < "$4"
    fi;
}

run_test() {

    cleanup "no-shut-down"

    parent_alg=$1
    name_alg=$2

    tpm2_createprimary -Q -G "$parent_alg" -g "$name_alg" -C o -c parent.ctx

    # 128 bit AES is 16 bytes
    run_aes_import_test parent.ctx aes-128-cfb 16
    # 256 bit AES is 32 bytes
    run_aes_import_test parent.ctx aes-256-cfb 32

    run_rsa_import_test parent.ctx 1024
    run_rsa_import_test parent.ctx 2048

    run_ecc_import_test parent.ctx prime256v1
}

#
# Run the tests against:
#   - RSA2048 with AES CFB 128 and 256 bit parents
#   - SHA256 object (not parent) name algorithms
#
parent_algs=("rsa2048:aes128cfb" "rsa2048:aes256cfb" "ecc256:aes128cfb")
halgs=`populate_hash_algs 'and alg != "sha1"'`
echo "halgs: $halgs"
for pa in "${parent_algs[@]}"; do
  for name in $halgs; do
    echo "$pa - $name"
    run_test "$pa" "$name"
  done;
done;

#
# Test the passin options
#

tpm2_createprimary -Q -c parent.ctx

openssl genrsa -aes128 -passout "pass:mypassword" -out "private.pem" 1024

run_rsa_import_passin_test "parent.ctx" "private.pem" "pass:mypassword"

export envvar="mypassword"
run_rsa_import_passin_test "parent.ctx" "private.pem" "env:envvar"

echo -n "mypassword" > "passfile"
run_rsa_import_passin_test "parent.ctx" "private.pem" "file:passfile"

exec 42<> passfile
run_rsa_import_passin_test "parent.ctx" "private.pem" "fd:42"

run_rsa_import_passin_test "parent.ctx" "private.pem" "stdin" "passfile"

exit 0
