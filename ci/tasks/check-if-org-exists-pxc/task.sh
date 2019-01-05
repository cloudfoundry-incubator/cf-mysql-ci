#!/bin/bash

set -eux

my_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ci_dir="${my_dir}/../../"
workspace_dir="${ci_dir}/../"

source ${ci_dir}/scripts/utils.sh
credhub_login

api_url="api.$(cf_domain)"

cf login -a ${api_url} -u $(cf_admin_username) -p $(cf_admin_password) -o pipeline-test-org --skip-ssl-validation

cf logout
