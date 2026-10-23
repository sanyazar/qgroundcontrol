#!/usr/bin/env bash
# Prints the QGroundControl-Bastion package version:
#
#   <QGC version>+bastion<fork version>[~<branch>]-<pipeline>
#   5.2.0~dev+bastion0.1.0~feat-multi-camera-57
#
#   QGC version   nearest upstream tag vX.Y.Z[-suffix] (git describe); "-dev" becomes "~dev", so a
#                 development snapshot sorts before the X.Y.Z release.
#   fork version  BASTION_VERSION at the repository root (semver, bumped when the fork changes).
#   ~<branch>     only for work-branch builds (not the default branch, not a tag); "~" sorts before
#                 the same version without it, so a release always supersedes branch builds.
#   pipeline      CI_PIPELINE_IID, the project's pipeline number: the Debian revision, so every
#                 pipeline produces a newer package than the one before.
#
# Usage: version.sh [--upstream|--fork|--build]   (default: the full Debian version)
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)

fork=$(tr -d '[:space:]' < "${root}/BASTION_VERSION")
if ! [[ "${fork}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "error: BASTION_VERSION must be X.Y.Z, got '${fork}'" >&2
    exit 1
fi

tag=$(git -C "${root}" describe --tags --abbrev=0 --match 'v[0-9]*' 2> /dev/null || echo v0.0.0)
upstream=${tag#v}
upstream=${upstream//-/\~}
upstream=$(tr -c 'A-Za-z0-9.~+\n' '.' <<< "${upstream}")

build=${CI_PIPELINE_IID:-0}

branch=""
if [ -z "${CI_COMMIT_TAG:-}" ] && [ -n "${CI_COMMIT_REF_SLUG:-}" ] \
    && [ "${CI_COMMIT_BRANCH:-}" != "${CI_DEFAULT_BRANCH:-}" ]; then
    branch="~${CI_COMMIT_REF_SLUG}"
fi

case "${1:-}" in
    --upstream) echo "${upstream}" ;;
    --fork) echo "${fork}" ;;
    --build) echo "${build}" ;;
    "") echo "${upstream}+bastion${fork}${branch}-${build}" ;;
    *)
        echo "usage: $0 [--upstream|--fork|--build]" >&2
        exit 2
        ;;
esac
