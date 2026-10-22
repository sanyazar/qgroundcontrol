#!/usr/bin/env bash
# Aligns and signs the release APK built by the Docker `android` image (which builds unsigned).
# Runs inside that image, where zipalign/apksigner/keytool are on PATH:
#   sign-apk.sh <unsigned.apk> <signed.apk>
# Signing key: base64 keystore in ANDROID_KEYSTORE_BASE64 with ANDROID_KEYSTORE_PASSWORD and
# ANDROID_KEY_ALIAS. Without it a throwaway key is generated: the APK installs, but a later
# build signed with another key cannot update it in place.
set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "usage: $0 <unsigned.apk> <signed.apk>" >&2
    exit 2
fi
input=$1
output=$2

work=$(mktemp -d)
trap 'rm -rf "${work}"' EXIT

keystore="${work}/release.jks"
if [ -n "${ANDROID_KEYSTORE_BASE64:-}" ]; then
    printf '%s' "${ANDROID_KEYSTORE_BASE64}" | base64 -d > "${keystore}"
    store_pass="${ANDROID_KEYSTORE_PASSWORD:?ANDROID_KEYSTORE_PASSWORD is required with a keystore}"
    alias="${ANDROID_KEY_ALIAS:?ANDROID_KEY_ALIAS is required with a keystore}"
else
    echo "::warning::No Android signing key configured; signing with a throwaway key." >&2
    store_pass=$(head -c 24 /dev/urandom | base64)
    alias=bastion
    keytool -genkeypair -noprompt -keystore "${keystore}" -storepass "${store_pass}" -keypass "${store_pass}" \
        -alias "${alias}" -keyalg RSA -keysize 3072 -validity 10000 -dname "CN=QGroundControl-Bastion CI"
fi

export QGC_KS_PASS="${store_pass}"
zipalign -p -f 4 "${input}" "${work}/aligned.apk"
apksigner sign --ks "${keystore}" --ks-key-alias "${alias}" --ks-pass env:QGC_KS_PASS \
    --out "${output}" "${work}/aligned.apk"
apksigner verify "${output}"
echo "Signed ${output}"
