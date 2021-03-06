# SPDX-License-Identifier: BSD-3-Clause

source helpers.sh

cleanup() {
    rm -f session.ctx secret.dat private.pem public.pem signature.dat \
    signing_key.ctx policy.signed prim.ctx sealing_key.priv sealing_key.pub \
    unsealed.dat qual.dat nonce.test time.out tic.ket authobj.name to_sign.bin \
    temp.bin

    tpm2_flushcontext session.ctx 2>/dev/null || true

    if [ "${1}" != "no-shutdown" ]; then
        shut_down
    fi
}
trap cleanup EXIT

start_up

cleanup "no-shutdown"


EXPIRYTIME="FFFFFE0C"
echo "plaintext" > secret.dat

#
# Test with policysigned
#
# Create the signing authority
openssl genrsa -out private.pem 2048
openssl rsa -in private.pem -outform PEM -pubout -out public.pem
# Load the verification key and Create the policysigned policy
tpm2_loadexternal -C o -G rsa -u public.pem -c signing_key.ctx \
-n signing_key.name

# Generate signature with nonceTPM, cpHashA, policyRef and expiration set to 0
echo $EXPIRYTIME | xxd -r -p > to_sign.bin
openssl dgst -sha256 -sign private.pem -out signature.dat to_sign.bin

tpm2_startauthsession -S session.ctx
tpm2_policysigned -S session.ctx -g sha256 -s signature.dat -f rsassa \
-c signing_key.ctx -L policy.signed
tpm2_flushcontext session.ctx

# Create a sealing object to use the policysigned
tpm2_createprimary -C o -c prim.ctx -Q
tpm2_create -u sealing_key.pub -r sealing_key.priv -c sealing_key.ctx \
-C prim.ctx -i secret.dat -L policy.signed -Q

# Create a policy ticket for policysigned
tpm2_startauthsession -S session.ctx --nonce-tpm=nonce.test --policy-session

echo $EXPIRYTIME | xxd -r -p > temp.bin
cat nonce.test temp.bin > to_sign.bin
openssl dgst -sha256 -sign private.pem -out signature.dat to_sign.bin

tpm2_policysigned -S session.ctx -g sha256 -s signature.dat -f rsassa \
-c signing_key.ctx -x nonce.test --ticket tic.ket --timeout time.out \
-t 0xFFFFFE0C

tpm2_flushcontext session.ctx

# Satisfy the policyticket and unseal the secret
tpm2_startauthsession -S session.ctx --policy-session

tpm2_policyticket -S session.ctx -n signing_key.name --ticket tic.ket \
--timeout time.out

tpm2_unseal -p session:session.ctx -c sealing_key.ctx -o unsealed.dat

tpm2_flushcontext session.ctx

diff secret.dat unsealed.dat

rm -f unsealed.dat

#
# Test with policysecret
#
tpm2_clear

tpm2_startauthsession -S session.ctx
tpm2_policysecret -S session.ctx -c o -L policy.secret
tpm2_flushcontext session.ctx

tpm2_createprimary -C o -c prim.ctx -Q
tpm2_create -Q -g sha256 -u sealing_key.pub -r sealing_key.priv -C prim.ctx \
-L policy.secret -i secret.dat
tpm2_load -C prim.ctx -u sealing_key.pub -r sealing_key.priv -c sealing_key.ctx

tpm2_startauthsession -S session.ctx --policy-session --nonce-tpm=nonce.test
tpm2_policysecret -S session.ctx -c o -t 0xFFFFFE0C --timeout time.out \
--ticket tic.ket --nonce-tpm nonce.test
tpm2_flushcontext session.ctx

TPM2_RH_OWNER="40000001"
echo $TPM2_RH_OWNER | xxd -r -p > authobj.name
tpm2_startauthsession -S session.ctx --policy-session
tpm2_policyticket -S session.ctx -n authobj.name --ticket tic.ket \
--timeout time.out
tpm2_unseal -p"session:session.ctx" -c sealing_key.ctx -o unsealed.dat
tpm2_flushcontext session.ctx

diff secret.dat unsealed.dat

exit 0
