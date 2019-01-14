#!/bin/bash

set -eux

MY_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CI_DIR="$( cd "${MY_DIR}/../../" && pwd )"
WORKSPACE_DIR="${WORKSPACE_DIR:-$( cd "${MY_DIR}/../../../" && pwd )}"
RELEASE_DIR="${RELEASE_DIR:-$(cd "${WORKSPACE_DIR}/cf-mysql-release" && pwd )}"

source "${CI_DIR}/scripts/utils.sh"

: "${ENV_TARGET_FILE:?}"
: "${BOSH_DEPLOYMENT:?}"
: "${BOSH_CLIENT:?}"
: "${BOSH_CLIENT_SECRET:?}"

export BOSH_ENVIRONMENT="$(cat "${ENV_TARGET_FILE}")"
export BOSH_CA_CERT="$WORKSPACE_DIR/bosh-lite-info/ca-cert"
SSH_KEY_FILE="${WORKSPACE_DIR}/bosh-lite-info/jumpbox-private-key"

bosh_ip=$(cat $WORKSPACE_DIR/bosh-lite-info/external-ip)

instances_file=$(mktemp)
bosh instances --column instance --column ips > $instances_file
broker_0_ip=$(cat $instances_file | awk '/broker\// {print $2}' | head -1)
broker_1_ip=$(cat $instances_file | awk '/broker\// {print $2}' | tail -1)
mysql_0_ip=$(cat $instances_file | awk '/mysql\// {print $2}' | head -1)

export BROKER_0_REMOTE_IP=$broker_0_ip
export BROKER_1_REMOTE_IP=$broker_1_ip
export MYSQL_NODE_0_REMOTE_IP=$mysql_0_ip

# assumes we are running against a remote bosh-lite
export BROKER_0_LOCAL_PORT="43306"
export BROKER_1_LOCAL_PORT="43307"
export MYSQL_NODE_0_LOCAL_PORT="43305"

# turn off the resurrector so that `scan-and-fix` tasks don't collide with our tests
bosh update-resurrection off

bosh manifest > /tmp/mysql-manifest.yml
PROXY_API_PASSWORD=$(bosh int /tmp/mysql-manifest.yml --path /instance_groups/name=proxy/jobs/name=proxy/properties/cf_mysql/proxy/api_password)

bosh -d cf manifest > /tmp/cf-manifest.yml
CF_API_PASSWORD=$(bosh int /tmp/cf-manifest.yml --path /instance_groups/name=uaa/jobs/name=uaa/properties/uaa/scim/users/name=admin/password)
DOMAIN=$(bosh int /tmp/cf-manifest.yml --path /instance_groups/name=api/jobs/name=cloud_controller_ng/properties/app_domains/0)

cat <<EOF > /tmp/env_metadata.json
{
  "cf_api_user": "admin",
  "cf_api_password": "${CF_API_PASSWORD}",
  "proxy_api_user": "proxy",
  "proxy_api_password": "${PROXY_API_PASSWORD}",
  "domain": "${DOMAIN}",
  "bosh_client": "${BOSH_CLIENT}",
  "bosh_client_secret":"${BOSH_CLIENT_SECRET}",
  "bosh_ca_cert_path": "${BOSH_CA_CERT}",
  "bosh_url": "${bosh_ip}"
}
EOF

export ENV_METADATA=/tmp/env_metadata.json

export CONFIG_LOCATION="${CI_DIR}/integration_config.json"
export BOSH_LITE_METADATA
${CI_DIR}/scripts/bosh/create_integration_test_config

source ${RELEASE_DIR}/.envrc # To set GOPATH to release dir
pushd ${RELEASE_DIR}/src/github.com/cloudfoundry-incubator/cf-mysql-acceptance-tests/
  export CONFIG="${CONFIG_LOCATION}"
  echo "Running tests ..."
  ./bin/test-failover --noColor
popd
