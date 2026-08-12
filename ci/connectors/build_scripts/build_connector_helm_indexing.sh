#!/usr/bin/env bash
set -euo pipefail

export TZ=Asia/Kolkata

# Merge index entries for packaged charts without resetting `created` on prior releases.
# Pass chart directory names (same as helm package args); omit args for legacy full re-index.
#
# See https://github.com/helm/helm/issues/7363

REPO_URL="https://aerospike.github.io/helm-charts"
INDEX_FILE="docs/index.yaml"

if [ "$#" -eq 0 ]; then
  helm repo index docs --merge "${INDEX_FILE}" --url "${REPO_URL}"
  exit 0
fi

staging="$(mktemp -d)"
trap 'rm -rf "${staging}"' EXIT

for chart in "$@"; do
  version="$(grep '^version:' "${chart}/Chart.yaml" | head -n1 | awk '{print $2}' | tr -d '"')"
  cp "docs/${chart}-${version}.tgz" "${staging}/"
done

helm repo index "${staging}" --merge "${INDEX_FILE}" --url "${REPO_URL}"
mv "${staging}/index.yaml" "${INDEX_FILE}"
