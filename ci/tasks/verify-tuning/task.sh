#!/bin/bash

set -eux
set -o pipefail

tmpdir=$(mktemp -d /tmp/mysql_tuning.XXXXX)
trap '{ rm -rf ${tmpdir}; }' EXIT

WORKSPACE_DIR="$(pwd)"
CI_DIR="${WORKSPACE_DIR}/cf-mysql-ci/"
MY_DIR="${CI_DIR}/ci/tasks/verify-tuning/"
MYSQL_CONFIG=${MY_DIR}/mysql.config

source ${CI_DIR}/scripts/utils.sh

: "${ENV_TARGET_FILE:?}"
: "${BOSH_DEPLOYMENT:?}"
: "${BOSH_CLIENT:?}"
: "${BOSH_CLIENT_SECRET:?}"

director_ip="$(cat "${ENV_TARGET_FILE}")"

export BOSH_ENVIRONMENT="$(cat "${ENV_TARGET_FILE}")"
export BOSH_CA_CERT="${WORKSPACE_DIR}/bosh-lite-info/ca-cert"

DEPLOYMENT_NAME=${DEPLOYMENT_NAME:-${BOSH_DEPLOYMENT:-"cf-warden-mysql"}}
SSH_KEY_FILE=${SSH_KEY_FILE:-""}
MYSQL_TUNNEL_IP=127.0.0.1
MYSQL_TUNNEL_PORT=3307
MYSQL_TUNNEL_USERNAME=${MYSQL_TUNNEL_USERNAME:-ubuntu}
MYSQL_VM_IP="$(bosh vms --column Instance --column IPs | grep mysql | awk '{print $2}' | head -1)"
MYSQL_VM_PORT=3306

function deploy_with_exact_size() {
  echo "Deploying with innodb_buffer_pool_size with exact size requirements"
  MANIFEST_FILE="${tmpdir}/bosh_lite_manifest.yml"

  TUNE_BY_EXACT_SIZE=true \
  OUTPUT_FILE="${MANIFEST_FILE}" \
  ${CI_DIR}/scripts/bosh-lite/make-manifest

  bosh vms
  bosh -n deploy $MANIFEST_FILE
  bosh vms
}

function deploy_with_percentage() {
  echo "Deploying with innodb_buffer_pool_size with size as percentage of total memory"
  MANIFEST_FILE="${tmpdir}/bosh_lite_manifest.yml"

  TUNE_BY_PERCENTAGE=true \
  OUTPUT_FILE="${MANIFEST_FILE}" \
  ${CI_DIR}/scripts/bosh-lite/make-manifest

  bosh -n deploy $MANIFEST_FILE
}

function deploy_with_everything_enabled() {
  echo "Deploying with the opsfile specified in cf-mysql-acceptance-tests, enabling all features"
  MANIFEST_FILE="${tmpdir}/bosh_lite_manifest.yml"

  EVERYTHING_ENABLED=true \
  OUTPUT_FILE="${MANIFEST_FILE}" \
  ${CI_DIR}/scripts/bosh-lite/make-manifest

  bosh -n deploy $MANIFEST_FILE
}

function deploy_with_ssl_disabled() {
  echo "Deploying without TLS"
  MANIFEST_FILE="${tmpdir}/bosh_lite_manifest.yml"

  ADD_TLS=false \
  OUTPUT_FILE="${MANIFEST_FILE}" \
  ${CI_DIR}/scripts/bosh-lite/make-manifest

  bosh -n deploy $MANIFEST_FILE
}

function deploy_with_ssl_enabled() {
  echo "Deploying with cf-mysql-deployment/operations/add-tls.yml"
  MANIFEST_FILE="${tmpdir}/bosh_lite_manifest.yml"

  ADD_TLS=true \
  FAKE_CA=true \
  OUTPUT_FILE="${MANIFEST_FILE}" \
  ${CI_DIR}/scripts/bosh-lite/make-manifest

  bosh -n deploy $MANIFEST_FILE
}

function deploy_with_everything_disabled() {
  echo "Deploying with the opsfile specified in cf-mysql-acceptance-tests, disabling all toggable features"
  MANIFEST_FILE="${tmpdir}/bosh_lite_manifest.yml"

  EVERYTHING_DISABLED=true \
  OUTPUT_FILE="${MANIFEST_FILE}" \
  ${CI_DIR}/scripts/bosh-lite/make-manifest

  bosh -n deploy $MANIFEST_FILE
}

function connect_to_mysql() {
  bosh vms
  write_mysql_config
  trap close-ssh-tunnels EXIT
  open_ssh_tunnel_to_mysql
}

function verify_exact_settings() {
  # look at db to see that it is exact
  innodb_bp_size=$(mysql --defaults-extra-file=${MYSQL_CONFIG} \
    -sse "SELECT @@innodb_buffer_pool_size")

  if [[ "${innodb_bp_size}" != "465567744" ]]; then
    echo "Exact size did not render correctly, found ${innodb_bp_size}"
    exit 1
  fi
}

function verify_percentage_settings() {
  # look at db to see it is not the old exact value
  innodb_bp_size=$(mysql --defaults-extra-file=${MYSQL_CONFIG} \
    -sse "SELECT @@innodb_buffer_pool_size")

  if [[ "${innodb_bp_size}" == "465567744" ]]; then
    echo "Percentage accidentally rendered old exact value, found ${innodb_bp_size}"
    exit 1
  fi
}

function verify_ssl_disabled() {
  is_ssl_enabled=$(mysql --defaults-extra-file=${MYSQL_CONFIG} \
    -sse "select @@have_ssl")

  if [[ "${is_ssl_enabled}" != "DISABLED" ]]; then
    echo "Somehow SSL is enabled in a default cf-mysql-release deployment"
    exit 1
  fi
}

function verify_ssl_enabled_but_not_connected_via_ssl() {
  is_ssl_enabled=$(mysql --defaults-extra-file=${MYSQL_CONFIG} \
    -sse "select @@have_ssl")
  ssl_cipher=$(mysql --defaults-extra-file=${MYSQL_CONFIG} --ssl=0 \
    -sse "status" | grep 'SSL')

  if [[ "${is_ssl_enabled}" != "YES" ]]; then
    echo "SSL is not enabled"
    exit 1
  fi

  if [[ "${ssl_cipher}" != *"Not in use"* ]]; then
    echo "The client connection is using SSL even when not asking to."
    exit 1
  fi
}

function verify_ssl_enabled_and_connected_via_ssl() {
  is_ssl_enabled=$(mysql --defaults-extra-file=${MYSQL_CONFIG} \
    -sse "select @@have_ssl")
  ssl_cipher=$(mysql --defaults-extra-file=${MYSQL_CONFIG} --ssl-cipher=DHE-RSA-AES256-SHA --ssl \
    -sse "status" | grep 'SSL')

  if [[ "${is_ssl_enabled}" != "YES" ]]; then
    echo "SSL is not enabled"
    exit 1
  fi

  if [[ "${ssl_cipher}" != *"Cipher in use is DHE-RSA-AES256-SHA"* ]]; then
    echo "The client connection is not using SSL even when asking to."
    exit 1
  fi
}

function create_acceptance_test_config() {
  local expectation_file_path
  expectation_file_path=$1

cat <<EOF
{
  "api": "",
  "apps_domain": null,
  "admin_user": "",
  "admin_password": "",
  "test_password": "",
  "broker_host": "",
  "service_name": "",
  "skip_ssl_validation": false,
  "proxy": {
    "dashboard_urls": [
      "https://0-proxy-",
      "https://1-proxy-"
    ],
    "api_username": "proxy",
    "api_password": "password",
    "api_force_https": true,
    "skip_ssl_validation": false
  },
  "standalone_only": true,
  "standalone": {
    "host": "${MYSQL_TUNNEL_IP}",
    "port": ${MYSQL_TUNNEL_PORT},
    "username": "root",
    "password": "password"
  },
  "tuning": {
    "expectation_file_path": "${expectation_file_path}"
  }
}
EOF
}

function verify_everything_enabled() {
  export GOPATH="${WORKSPACE_DIR}/cf-mysql-release"
  export PATH=$GOPATH/bin:$PATH

  go install -v github.com/onsi/ginkgo/ginkgo

  pushd "${WORKSPACE_DIR}/cf-mysql-release/src/github.com/cloudfoundry-incubator/cf-mysql-acceptance-tests"
    create_acceptance_test_config \
      "${PWD}/assets/tuning/everything_enabled.json" \
      > /tmp/everything_enabled_config.json

    CONFIG=/tmp/everything_enabled_config.json ginkgo cf-mysql-service/tuning
  popd
}

function verify_everything_disabled() {
  export GOPATH="${WORKSPACE_DIR}/cf-mysql-release"
  export PATH=$GOPATH/bin:$PATH

  go install -v github.com/onsi/ginkgo/ginkgo

  pushd "${WORKSPACE_DIR}/cf-mysql-release/src/github.com/cloudfoundry-incubator/cf-mysql-acceptance-tests"
    create_acceptance_test_config \
      "${PWD}/assets/tuning/everything_disabled.json" \
      > /tmp/everything_disabled_config.json

    CONFIG=/tmp/everything_disabled_config.json ginkgo cf-mysql-service/tuning
  popd
}


deploy_with_exact_size
connect_to_mysql
verify_exact_settings

deploy_with_percentage
verify_percentage_settings

deploy_with_ssl_disabled
verify_ssl_disabled

deploy_with_ssl_enabled
verify_ssl_enabled_but_not_connected_via_ssl
verify_ssl_enabled_and_connected_via_ssl

echo "Tuning overriding works with exact and percentage"

deploy_with_everything_enabled
verify_everything_enabled

deploy_with_everything_disabled
verify_everything_disabled
