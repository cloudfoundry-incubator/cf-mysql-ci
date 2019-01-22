#!/usr/bin/env bash

set -eux

WORKSPACE_DIR="$( pwd )"

CI_DIR="${WORKSPACE_DIR}/cf-mysql-ci"
TEST_DATA_SCHEMA_PATH="${CI_DIR}/ci/tasks/run-data-loss-tests/setup-test-data-schema.sql"


: "${ENV_TARGET_FILE:?}"
: "${BOSH_DEPLOYMENT:?}"
: "${BOSH_CLIENT:?}"
: "${BOSH_CLIENT_SECRET:?}"

source ${CI_DIR}/scripts/utils.sh

export BOSH_ENVIRONMENT="$(cat "${ENV_TARGET_FILE}")"
export BOSH_CA_CERT="${WORKSPACE_DIR}/bosh-lite-info/ca-cert"

MYSQL_TUNNEL_RELAY=${BOSH_ENVIRONMENT#https://}
MYSQL_TUNNEL_PORT=3307
MYSQL_TUNNEL_USERNAME=jumpbox
MYSQL_VM_IP=10.244.7.2
MYSQL_VM_PORT=3306
GCACHE_SIZE_PLUS_ONE=513

# Figure out the name of mysql z2
MYSQL_NODE_NAME=`bosh instances | grep "mysql/" | grep "z2" | cut -d ' ' -f 1`

function close-ssh-tunnels() {
  echo "Closing SSH tunnels ..."
  OLD_TUNNELS=`ps aux | grep "ssh" | grep "\-L $MYSQL_TUNNEL_PORT" | awk '{print $2}'`
  [[ -z "${OLD_TUNNELS}" ]] || kill ${OLD_TUNNELS}
}

function open_ssh_tunnel_to_bosh_lite() {
  SSH_KEY_FILE="${WORKSPACE_DIR}/bosh-lite-info/jumpbox-private-key"

  ssh -L ${MYSQL_TUNNEL_PORT}:${MYSQL_VM_IP}:${MYSQL_VM_PORT} \
    -nNTf \
    -o StrictHostKeyChecking=no \
    -i "${SSH_KEY_FILE}" \
    ${MYSQL_TUNNEL_USERNAME}@${MYSQL_TUNNEL_RELAY}
}

function stop_mysql_z2() {
  bosh -n stop ${MYSQL_NODE_NAME}
}

function write_data_to_overflow_gcache() {

  MYSQL_HOST=127.0.0.1
  MYSQL_PORT=${MYSQL_TUNNEL_PORT}

  mysql --host=${MYSQL_HOST} \
    --port=${MYSQL_PORT} \
    --user=root \
    --password=password < ${TEST_DATA_SCHEMA_PATH}

  for i in `seq 1 ${GCACHE_SIZE_PLUS_ONE}`;
  do
    echo "INSERT INTO test_table(id, text) VALUES ('${i}', REPEAT('A', 1024 * 1024));"
  done |  mysql --host=${MYSQL_HOST} \
    --port=${MYSQL_PORT} \
    --user=root \
    --password=password \
    --database=mysql_data_loss_test
}

function attempt_to_start_mysql_z2() {
  set +e
  bosh -n start ${MYSQL_NODE_NAME}
  set -e
}

function assert_mysql_z2_did_not_join() {
  for i in $(seq 1 10); do
    cluster_size=$(mysql --host=${MYSQL_HOST} \
      --port=${MYSQL_PORT} \
      --user=root \
      --password=password \
      --skip-column-names \
      --silent \
      -e "show status like 'wsrep_cluster_size'" 2>/dev/null | awk '{print $NF}')

    echo "Attempt #${i}: Cluster size is: ${cluster_size}"

    if [ "${cluster_size}" == "2" ]; then
      exit 0
    fi
    sleep 1
  done

  echo "Cluster size never converged to 2, is at: ${cluster_size}"
  exit 1
}

trap close-ssh-tunnels EXIT

open_ssh_tunnel_to_bosh_lite
stop_mysql_z2
write_data_to_overflow_gcache
attempt_to_start_mysql_z2
assert_mysql_z2_did_not_join
