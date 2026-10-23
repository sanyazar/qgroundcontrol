#!/usr/bin/env bash
# Uploads the packages in <dir> to the GitLab generic package registry and creates a release for
# CI_COMMIT_TAG linking them. Runs in GitLab CI with the job token; needs curl and python3.
# Usage: publish-release.sh <dir>
set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "usage: $0 <dir>" >&2
    exit 2
fi
dir=$1
: "${CI_API_V4_URL:?}" "${CI_PROJECT_ID:?}" "${CI_COMMIT_TAG:?}" "${CI_JOB_TOKEN:?}"

registry="${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/packages/generic/qgroundcontrol-bastion/${CI_COMMIT_TAG#v}"
links_file=$(mktemp)
trap 'rm -f "${links_file}"' EXIT

shopt -s nullglob
files=("${dir}"/*)
if [ "${#files[@]}" -eq 0 ]; then
    echo "error: no packages found in ${dir}" >&2
    exit 1
fi
for file in "${files[@]}"; do
    name=${file##*/}
    echo "Uploading ${name}"
    curl --fail --silent --show-error --header "JOB-TOKEN: ${CI_JOB_TOKEN}" \
        --upload-file "${file}" "${registry}/${name}" > /dev/null
    printf '%s\t%s\n' "${name}" "${registry}/${name}" >> "${links_file}"
done

payload=$(python3 - "${links_file}" <<'PY'
import json, os, sys
links = []
with open(sys.argv[1], encoding="utf-8") as f:
    for line in f:
        name, url = line.rstrip("\n").split("\t")
        links.append({"name": name, "url": url, "link_type": "package"})
tag = os.environ["CI_COMMIT_TAG"]
print(json.dumps({
    "name": f"QGroundControl Bastion {tag}",
    "tag_name": tag,
    "description": f"Packages built from {tag}.",
    "assets": {"links": links},
}))
PY
)
curl --fail --silent --show-error --header "JOB-TOKEN: ${CI_JOB_TOKEN}" --header "Content-Type: application/json" \
    --data "${payload}" "${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/releases" > /dev/null
echo "Release ${CI_COMMIT_TAG} created with ${#files[@]} files"
