#!/bin/bash
set -eu

MY_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CI_DIR="$( cd ${MY_DIR}/../../ && pwd )"
WORKSPACE_DIR="$( cd ${MY_DIR}/../../.. && pwd )"
MYSQL_CONFIG=${MY_DIR}/mysql.config

: "${ENV_TARGET_FILE:?}"
: "${BOSH_CLIENT}"
: "${BOSH_CLIENT_SECRET}"

source ${CI_DIR}/scripts/utils.sh

director_url="$(cat "${ENV_TARGET_FILE}")"
director_ip="$(cat "${DIRECTOR_IP}")"

export BOSH_ENVIRONMENT="$(sslip_from_ip "${director_url}")"
export BOSH_DEPLOYMENT="cf-mysql"
SSH_KEY_FILE=${SSH_KEY_FILE:-""}
MYSQL_TUNNEL_IP=127.0.0.1
MYSQL_TUNNEL_PORT=3307
MYSQL_TUNNEL_USERNAME=${MYSQL_TUNNEL_USERNAME:-ubuntu}
MYSQL_VM_IP=10.244.7.2
MYSQL_VM_PORT=3306
HEALTHCHECK_PORT=9200
HEALTHCHECK_USER=username
HEALTHCHECK_PASSWORD=password

function open_ssh_tunnel_to_bosh_lite() {
  if [[ -z "${SSH_KEY_FILE}" ]]; then
      SSH_KEY_FILE="bosh-key"
      echo "${BOSH_SSH_KEY}" > "${SSH_KEY_FILE}"
      chmod 600 "${SSH_KEY_FILE}"
  fi

  ssh -L ${MYSQL_TUNNEL_PORT}:${MYSQL_VM_IP}:${MYSQL_VM_PORT} \
    -L ${HEALTHCHECK_PORT}:${MYSQL_VM_IP}:${HEALTHCHECK_PORT} \
    -nNTf \
    -o StrictHostKeyChecking=no \
    -i "${SSH_KEY_FILE}" \
    ${MYSQL_TUNNEL_USERNAME}@${director_ip}
}

function verify_schemas() {
  output="$(bosh run-errand verify-cluster-schemas --keep-alive)"
  echo $output
}

function drop_test_database_if_exists() {
  mysql --defaults-extra-file=${MYSQL_CONFIG} \
    -e "drop database if exists force_divergent_schemas_test"
}

function update_osu_method() {
  OSU_METHOD=$1

  mysql --defaults-extra-file=${MYSQL_CONFIG} \
    -e "set global wsrep_osu_method=${OSU_METHOD}"
}

function update_schema_on_one_node() {
  mysql --defaults-extra-file=${MYSQL_CONFIG} \
    -e "create database force_divergent_schemas_test"
}

function confirm_schemas_are_equivalent() {
  set +e
  output=$(verify_schemas)
  echo ${output}
  echo ${output} | grep "Success: All schemas are equal"

  if [ $? != "0" ]; then
    echo "Error: Initial schemas are out of sync"
    exit 1
  fi
  set -e
}

function confirm_schemas_are_out_of_sync() {
  set +e
  output=$(verify_schemas)
  echo ${output}
  echo ${output} | grep "Error: Cluster schemas are not consistent"

  if [ $? != "0" ]; then
    echo "Error: Schemas should be out of sync, but report in sync"
    exit 1
  fi
  set -e
  echo "Success: Schemas are now diverged!"
}

function stop_mysql_on_node() {
  curl -X POST http://${HEALTHCHECK_USER}:${HEALTHCHECK_PASSWORD}@127.0.0.1:${HEALTHCHECK_PORT}/stop_mysql
  sleep 6
}

write_mysql_config

trap close-ssh-tunnels EXIT
open_ssh_tunnel_to_bosh_lite

drop_test_database_if_exists
update_osu_method "TOI"

confirm_schemas_are_equivalent

update_osu_method "RSU"
update_schema_on_one_node

stop_mysql_on_node

confirm_schemas_are_out_of_sync

exit 0
