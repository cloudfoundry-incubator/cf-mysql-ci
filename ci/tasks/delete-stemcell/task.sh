#!/bin/bash
set -eux

my_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
workspace_dir="$( cd "${my_dir}/../../../" && pwd )"
bosh_lite_dir="deployments/bosh-lite-gcp"

service_key="${bosh_lite_dir}/ci-service-account.json"

gcloud auth activate-service-account --key-file=${service_key}
gcloud config set project cf-core-services

stemcell_id=$(bosh int "${workspace_dir}/bosh-lite-info/bosh-state.json" --path /stemcells/0/cid)

echo "Deleting stemcell ${stemcell_id}"

gcloud compute images delete \
        ${stemcell_id} \
        --quiet

cp ${workspace_dir}/bosh-lite-info/* ${workspace_dir}/bosh-lite-info-stemcell-deleted/

pushd "${workspace_dir}/bosh-lite-info-stemcell-deleted"
    cat bosh-state.json | jq "del(.stemcells[0])" > bosh-state.json.new
    mv bosh-state.json.new bosh-state.json
popd
