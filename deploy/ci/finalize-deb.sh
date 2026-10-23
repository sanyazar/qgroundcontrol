#!/usr/bin/env bash
# Checks the native .deb built by the Docker image in <build-dir>, sets its version to <version>
# (see deploy/ci/version.sh) and tags the file name with the Ubuntu release it was built for
# (a native .deb links against its release's ffmpeg/libvpx):
#   qgroundcontrol-bastion_<version>_ubuntu<release>_amd64.deb
# Usage: finalize-deb.sh <build-dir> <ubuntu-release> <version>
set -euo pipefail

if [ "$#" -ne 3 ]; then
    echo "usage: $0 <build-dir> <ubuntu-release> <version>" >&2
    exit 2
fi
build_dir=$1
release=$2
version=$3

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
work=$(mktemp -d)
trap 'rm -rf "${work}"' EXIT
dpkg-deb --raw-extract "${deb}" "${work}/pkg"
sed -i "s/^Version: .*/Version: ${version}/" "${work}/pkg/DEBIAN/control"
tagged="${build_dir}/${name}_${version}_ubuntu${release}_${arch}.deb"
dpkg-deb --root-owner-group -Zxz --build "${work}/pkg" "${tagged}" > /dev/null
rm -f "${deb}" "${deb}.sha256"
(cd "${build_dir}" && sha256sum "${tagged##*/}" > "${tagged##*/}.sha256")
echo "Built ${tagged##*/}"
echo "Depends: $(dpkg-deb --field "${tagged}" Depends)"
