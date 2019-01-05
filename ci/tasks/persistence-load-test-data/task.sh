#!/bin/bash

set -eux

WORKSPACE_DIR="$(pwd)"
SQL_QUERY_DIR="${WORKSPACE_DIR}/cf-mysql-ci/ci/tasks/persistence-load-test-data/test-data/"

: "${ENV_TARGET_FILE:?}"

BOSH_ENVIRONMENT="$(cat "${ENV_TARGET_FILE}")"

bosh_ip=$(echo "${BOSH_ENVIRONMENT}" | sed 's$https://$$g')

MYSQL_TUNNEL_IP=127.0.0.1
MYSQL_TUNNEL_PORT=3307
MYSQL_VM_IP="${MYSQL_VM_IP:-10.244.7.2}"
MYSQL_VM_PORT=3306

echo "Targeting remote bosh-lite, starting ssh tunnel..."

SSH_KEY_FILE="${WORKSPACE_DIR}/bosh-lite-info/jumpbox-private-key"

if [ -z "${BOSH_ENVIRONMENT}" ]; then
  echo "BOSH target file is empty"
  exit 1
fi

function close-ssh-tunnels() {
  echo "Closing SSH tunnels ..."
  OLD_TUNNELS=`ps aux | grep "ssh" | grep "\-L $MYSQL_TUNNEL_PORT" | awk '{print $2}'`
  [[ -z "${OLD_TUNNELS}" ]] || kill ${OLD_TUNNELS}
}

# open SSH tunnel to mysql container on bosh-lite
trap close-ssh-tunnels EXIT
ssh -L ${MYSQL_TUNNEL_PORT}:${MYSQL_VM_IP}:${MYSQL_VM_PORT} \
  -nNTf \
  -o StrictHostKeyChecking=no \
  -i "${SSH_KEY_FILE}" \
  jumpbox@${bosh_ip}

MYSQL_HOST=${MYSQL_TUNNEL_IP}
MYSQL_PORT=${MYSQL_TUNNEL_PORT}

pushd ${SQL_QUERY_DIR}
  echo "Inserting test data..."

  mysql --host=${MYSQL_HOST} \
    --port=${MYSQL_PORT} \
    --user=root \
    --password=password \
    < clean-bosh-lite-test-database.sql

  mysql --host=${MYSQL_HOST} \
    --port=${MYSQL_PORT} \
    --user=root \
    --password=password \
    mysql_persistence_test \
    < insert-test-data.sql
popd

echo "Successfully inserted test data"
