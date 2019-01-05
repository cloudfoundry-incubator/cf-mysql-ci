#!/usr/bin/env bash

MY_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
WORKSPACE_DIR="$( cd "${MY_DIR}/../../.." && pwd )"

stemcell_version="$(bosh int "${WORKSPACE_DIR}/cf-deployment-rc/cf-deployment.yml" --path=/stemcells/os=ubuntu-xenial/version)"
aria2c -x 4 -d ${WORKSPACE_DIR}/cf-deployment-rc-stemcell \
  https://s3.amazonaws.com/bosh-core-stemcells/google/bosh-stemcell-${stemcell_version}-google-kvm-ubuntu-xenial-go_agent.tgz
# the compile release script expects a version file in the stemcell folder
echo ${stemcell_version} > ${WORKSPACE_DIR}/cf-deployment-rc-stemcell/version
