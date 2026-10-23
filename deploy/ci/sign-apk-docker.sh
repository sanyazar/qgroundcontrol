#!/usr/bin/env bash
# Signs the APK built by the Docker `android` image, running deploy/android/sign-apk.sh inside
# that image (it has zipalign/apksigner/keytool). Signing key from ANDROID_KEYSTORE_BASE64,
# ANDROID_KEYSTORE_PASSWORD and ANDROID_KEY_ALIAS when set, otherwise a throwaway key.
# Usage: sign-apk-docker.sh <build-dir> <output-name>
set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "usage: $0 <build-dir> <output-name>" >&2
    exit 2
fi
build_dir=$(cd "$1" && pwd)
output=$2
source_dir=$(cd "$(dirname "$0")/../.." && pwd)

shopt -s nullglob
apks=("${build_dir}"/android-build/*.apk)
if [ "${#apks[@]}" -ne 1 ]; then
    echo "error: expected exactly one APK in ${build_dir}/android-build, found ${#apks[@]}" >&2
    exit 1
fi

docker run --rm --user "$(id -u):$(id -g)" --env HOME=/tmp \
    --env ANDROID_KEYSTORE_BASE64 --env ANDROID_KEYSTORE_PASSWORD --env ANDROID_KEY_ALIAS \
    -v "${source_dir}:/project/source:ro" -v "${build_dir}:/project/build" \
    --entrypoint /bin/bash qgc-android-docker -l \
    /project/source/deploy/android/sign-apk.sh \
    "/project/build/android-build/${apks[0]##*/}" "/project/build/${output}"
