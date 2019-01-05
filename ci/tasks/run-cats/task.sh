#!/bin/bash

set -eux

source "cf-mysql-ci/scripts/utils.sh"

credhub_login
system_domain=$(cat url/url)
admin_password=$(credhub_value /lite/cf/cf_admin_password)

cat > integration_config.json <<EOF
{
  "api": "api.${system_domain}",
  "apps_domain": "${system_domain}",
  "admin_user": "admin",
  "admin_password": "${admin_password}",
  "skip_ssl_validation": true,
  "use_http": true,
  "include_apps": true,
  "include_backend_compatibility": false,
  "include_capi_experimental": false,
  "include_capi_no_bridge": false,
  "include_container_networking": false,
  "include_credhub" : false,
  "include_detect": true,
  "include_docker": false,
  "include_internet_dependent": false,
  "include_isolation_segments": false,
  "include_persistent_app": false,
  "include_private_docker_registry": false,
  "include_privileged_container_support": false,
  "include_route_services": false,
  "include_routing": true,
  "include_routing_isolation_segments": false,
  "include_security_groups": true,
  "include_service_discovery": false,
  "include_services": true,
  "include_service_instance_sharing": false,
  "include_ssh": false,
  "include_sso": true,
  "include_tasks": true,
  "include_v3": true,
  "include_zipkin": false
}
EOF

dir=go/src/github.com/cloudfoundry
export CONFIG=$PWD/integration_config.json
mkdir -p $dir

cp -R cf-acceptance-tests $dir
cd $dir/cf-acceptance-tests

./bin/test -nodes=4 -slowSpecThreshold=500 -noisySkippings=false
