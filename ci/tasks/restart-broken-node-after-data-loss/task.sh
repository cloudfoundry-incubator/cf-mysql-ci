#!/bin/bash
set -eux

MY_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CI_DIR="$( cd ${MY_DIR}/../../ && pwd )"
WORKSPACE_DIR="$( cd ${MY_DIR}/../../.. && pwd )"

: "${ENV_TARGET_FILE:?}"
: "${BOSH_DEPLOYMENT:?}"
: "${BOSH_CLIENT:?}"
: "${BOSH_CLIENT_SECRET:?}"

export BOSH_ENVIRONMENT="$(cat "${ENV_TARGET_FILE}")"
export BOSH_CA_CERT="${WORKSPACE_DIR}/bosh-lite-info/ca-cert"

# Figure out the name of mysql z2
MYSQL_NODE_NAME=`bosh instances | grep "mysql/" | grep "z2" | cut -d ' ' -f 1`

bosh -n start ${MYSQL_NODE_NAME}
