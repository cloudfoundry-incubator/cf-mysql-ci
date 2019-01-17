#!/bin/bash
set -eu

MY_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CI_DIR="$( cd ${MY_DIR}/../../ && pwd )"
WORKSPACE_DIR="$( cd ${MY_DIR}/../../.. && pwd )"
MYSQL_CONFIG=${MY_DIR}/mysql.config

source "${WORKSPACE_DIR}/bosh-lite-info/source_me"

source ${CI_DIR}/scripts/utils.sh

: "${ENV_TARGET_FILE:?}"
: "${BOSH_CLIENT}"
: "${BOSH_CLIENT_SECRET}"

director_ip="$(cat "${ENV_TARGET_FILE}")"

DEPLOYMENT_NAME=${DEPLOYMENT_NAME:-${BOSH_DEPLOYMENT:-"cf-warden-mysql"}}
SSH_KEY_FILE=${SSH_KEY_FILE:-""}
MYSQL_TUNNEL_IP=127.0.0.1
MYSQL_TUNNEL_PORT=3307
MYSQL_TUNNEL_USERNAME=${MYSQL_TUNNEL_USERNAME:-ubuntu}
MYSQL_VM_IP="$(bosh vms --column Instance --column IPs | grep mysql | awk '{print $2}' | head -1)"
MYSQL_VM_PORT=3306

write_mysql_config
trap close-ssh-tunnels EXIT
open_ssh_tunnel_to_mysql

mysql --defaults-extra-file=${MYSQL_CONFIG} \
  -e "SELECT 1" 2>&1 | grep -q 'Access denied'
