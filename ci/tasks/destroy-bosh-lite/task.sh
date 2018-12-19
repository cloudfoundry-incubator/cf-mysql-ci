#!/bin/bash
set -eu

my_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ci_dir="$( cd "${my_dir}/../../" && pwd )"
workspace_dir="$( cd "${ci_dir}/../" && pwd )"

BOSH_LITE_INFO_DIR="${workspace_dir}/${BOSH_LITE_INFO_DIR}"

bosh delete-env "${BOSH_LITE_INFO_DIR}/manifest.yml" \
  --state "${BOSH_LITE_INFO_DIR}/bosh-state.json" \
  --vars-store "${BOSH_LITE_INFO_DIR}/bosh-creds.yml"

