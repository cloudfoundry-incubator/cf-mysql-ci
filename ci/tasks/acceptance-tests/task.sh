#!/usr/bin/env bash

set -eux

TEST_TYPE="acceptance"

WORKSPACE_DIR="$(pwd)"
CI_DIR="${WORKSPACE_DIR}/cf-mysql-ci"
RELEASE_DIR="$(cd "${WORKSPACE_DIR}/cf-mysql-release" && pwd )"

export PATH=$PATH:/usr/lib/chromium-browser/
export LD_LIBRARY_PATH=/usr/lib/chromium-browser/libs

export CONFIG_LOCATION="${CI_DIR}/integration-config.json"
"${CI_DIR}/scripts/bosh/create_integration_test_config_gcp"

export CONFIG="${CONFIG_LOCATION}"

# shellcheck disable=SC1090
source "${RELEASE_DIR}/.envrc"

# Remove and reinstall the ginkgo binary as it might be from the wrong target architecture
rm -rf "${RELEASE_DIR}/bin/ginkgo"
go install -v github.com/onsi/ginkgo/ginkgo

echo -e "\nRunning ${TEST_TYPE} tests"
pushd "${RELEASE_DIR}/src/github.com/cloudfoundry-incubator/cf-mysql-acceptance-tests/"
  "./bin/test-${TEST_TYPE}" "$@"
popd
