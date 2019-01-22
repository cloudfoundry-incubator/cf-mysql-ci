#!/bin/bash
set -eux

set_env(){
  WORKSPACE_DIR="$(pwd)"
  source "./cf-mysql-ci/scripts/utils.sh"

  : "${ENV_TARGET_FILE:?}"
  : "${BOSH_CLIENT:?}"
  : "${BOSH_CLIENT_SECRET:?}"

  bosh_ip=$(cat "${ENV_TARGET_FILE}")

  GALERA_HEALTHCHECK_USERNAME="${GALERA_HEALTHCHECK_USERNAME:-galera-healthcheck}"
}

stop_all_nodes() {
  pushd "${WORKSPACE_DIR}"
    SSH_KEY_FILE="${WORKSPACE_DIR}/bosh-lite-info/jumpbox-private-key"

    # stopping mysql on node0 and the arbitrator node
    for MYSQL_NODE in 10.244.7.2 10.244.8.2 10.244.9.2; do
      ssh \
          -t \
          -i "${SSH_KEY_FILE}" \
          -o StrictHostKeyChecking=no \
          "jumpbox@${bosh_ip}" \
          "curl -vkf -X POST ${GALERA_HEALTHCHECK_USERNAME}:password@${MYSQL_NODE}:9200/stop_mysql"
    done
  popd
}

main(){
    set_env
    stop_all_nodes
}

main
