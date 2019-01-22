#!/bin/bash

set -eux
set -o pipefail

gem install mysql2 json

WORKSPACE_DIR="$(pwd)"
CI_DIR="${WORKSPACE_DIR}/cf-mysql-ci"
MY_DIR="${CI_DIR}/ci/tasks/verify-tls-enabled"

source ${CI_DIR}/scripts/utils.sh

api_url="api.$(cf_domain)"

my_id=$RANDOM
service_instance="tls-service-instance-${my_id}"
service_instance_key="${service_instance}-key"

cf login -a ${api_url} -u $(cf_admin_username) -p $(cf_admin_password) --skip-ssl-validation
cf create-org test-org
cf target -o test-org
cf create-space test-space
cf target -s test-space

cf create-service p-mysql 10mb $service_instance
cf create-service-key $service_instance $service_instance_key
cf service-key $service_instance $service_instance_key | tail -n +3 > ${MY_DIR}/connection.json

${MY_DIR}/get_mysql_ssl_cipher.rb ${MY_DIR}/connection.json ${MY_DIR}/cipher

cipher=$(cat ${MY_DIR}/cipher)
if [[ "$cipher" == "" ]]; then
  echo "Test Failed: Did not connect to mysql using SSL"
  exit 1
fi
