#!/usr/bin/env bash
# Checks the .deb built by the Docker image in <build-dir> and tags its file name with the
# Ubuntu release it was built for (each .deb links against its release's ffmpeg/libvpx):
#   qgroundcontrol-bastion_<ver>_amd64.deb -> qgroundcontrol-bastion_<ver>_ubuntu<release>_amd64.deb
# Usage: finalize-deb.sh <build-dir> <ubuntu-release>
set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "usage: $0 <build-dir> <ubuntu-release>" >&2
    exit 2
fi
build_dir=$1
release=$2

shopt -s nullglob
debs=("${build_dir}"/*.deb)
if [ "${#debs[@]}" -ne 1 ]; then
    echo "error: expected exactly one .deb in ${build_dir}, found ${#debs[@]}" >&2
    exit 1
fi
deb=${debs[0]}

name=$(dpkg-deb --field "${deb}" Package)
if [ "${name}" != "qgroundcontrol-bastion" ]; then
    echo "error: unexpected package name '${name}'" >&2
    exit 1
fi
# Read the listing first: grep -q closing the pipe early makes dpkg-deb fail with SIGPIPE.
contents=$(dpkg-deb --contents "${deb}")
if ! grep -qF './usr/bin/QGroundControl-Bastion ->' <<< "${contents}"; then
    echo "error: launcher /usr/bin/QGroundControl-Bastion is missing" >&2
    exit 1
fi

arch=$(dpkg-deb --field "${deb}" Architecture)
tagged="${deb%_"${arch}".deb}_ubuntu${release}_${arch}.deb"
rm -f "${deb}.sha256"
mv "${deb}" "${tagged}"
(cd "${build_dir}" && sha256sum "${tagged##*/}" > "${tagged##*/}.sha256")
echo "Built ${tagged##*/}"
echo "Depends: $(dpkg-deb --field "${tagged}" Depends)"
