#!/bin/bash
set -eux

workspace_dir="$(pwd)"

cf_mysql_deployment_dir="${workspace_dir}/cf-mysql-deployment"

OUTPUT_DIR="${workspace_dir}/${OUTPUT_DIR}"
BOSH_DEPLOYMENT_DIR="${workspace_dir}/${BOSH_DEPLOYMENT_DIR}"
DEPLOYMENTS_DIR="${workspace_dir}/${DEPLOYMENTS_DIR}"
stemcell_dir="${workspace_dir}/stemcell"

: "${PROJECT_ID}"
: "${ZONE}"
: "${NETWORK}"
: "${SUBNETWORK}"
: "${BOSH_CLIENT_SECRET}"

bosh_lite_dir="${DEPLOYMENTS_DIR}/bosh-lite-gcp"

pushd "${bosh_lite_dir}" > /dev/null
  terraform output lite-external-ip > "${OUTPUT_DIR}/external-ip"
popd > /dev/null

bosh interpolate "${BOSH_DEPLOYMENT_DIR}/bosh.yml" \
  -o "${BOSH_DEPLOYMENT_DIR}/gcp/cpi.yml" \
  -o "${BOSH_DEPLOYMENT_DIR}/bosh-lite.yml" \
  -o "${BOSH_DEPLOYMENT_DIR}/bosh-lite-runc.yml" \
  -o "${BOSH_DEPLOYMENT_DIR}/bosh-lite-grootfs.yml" \
  -o "${BOSH_DEPLOYMENT_DIR}/external-ip-not-recommended.yml" \
  -o "${BOSH_DEPLOYMENT_DIR}/jumpbox-user.yml" \
  -o "${BOSH_DEPLOYMENT_DIR}/uaa.yml" \
  -o "${BOSH_DEPLOYMENT_DIR}/external-ip-not-recommended-uaa.yml" \
  -o "${BOSH_DEPLOYMENT_DIR}/credhub.yml" \
  -o "${bosh_lite_dir}/dynamic-network.yml" \
  -o "${bosh_lite_dir}/instance.yml" \
  -o "${bosh_lite_dir}/external-ip-not-recommended-credhub.yml" \
  -o "${bosh_lite_dir}/remove-blobstore.yml" \
  -o "${workspace_dir}/cf-mysql-ci/operations/enable-bosh-dns.yml" \
  -o "${workspace_dir}/cf-mysql-ci/operations/enable-remove-dev-tools.yml" \
  --vars-store "${OUTPUT_DIR}/bosh-creds.yml" \
  -v director_name=lite \
  -v internal_ip=127.0.0.1 \
  -v external_ip="$(cat "${OUTPUT_DIR}/external-ip")" \
  --var-file gcp_credentials_json="${bosh_lite_dir}/ci-service-account.json" \
  -v project_id="${PROJECT_ID}" \
  -v zone="${ZONE}" \
  -v network="${NETWORK}" \
  -v admin_password="${BOSH_CLIENT_SECRET}" \
  -v subnetwork="${SUBNETWORK}" > "${OUTPUT_DIR}/manifest.yml"

bosh create-env "${OUTPUT_DIR}/manifest.yml" \
  --state "${OUTPUT_DIR}/bosh-state.json" \
  --vars-store "${OUTPUT_DIR}/bosh-creds.yml"

bosh -n interpolate "${OUTPUT_DIR}/bosh-creds.yml" \
  --path /director_ssl/ca > "${OUTPUT_DIR}/ca-cert"

bosh -n interpolate "${OUTPUT_DIR}/bosh-creds.yml" \
  --path /jumpbox_ssh/private_key > "${OUTPUT_DIR}/jumpbox-private-key"
chmod 600 "${OUTPUT_DIR}/jumpbox-private-key"

bosh -n interpolate "${OUTPUT_DIR}/bosh-creds.yml" \
  --path /credhub_ca/ca > "${OUTPUT_DIR}/credhub.ca"

bosh -n interpolate "${OUTPUT_DIR}/bosh-creds.yml" \
  --path /uaa_ssl/ca > "${OUTPUT_DIR}/uaa.ca"

bosh -n upload-stemcell "${stemcell_dir}"/*.tgz \
  -e "$(cat "${OUTPUT_DIR}/external-ip")" \
  --client admin \
  --client-secret "${BOSH_CLIENT_SECRET}" \
  --ca-cert "${OUTPUT_DIR}/ca-cert"

bosh -n update-cloud-config "${cf_mysql_deployment_dir}/bosh-lite/cloud-config.yml" \
  -e "$(cat "${OUTPUT_DIR}/external-ip")" \
  --client admin \
  --client-secret "${BOSH_CLIENT_SECRET}" \
  --ca-cert "${OUTPUT_DIR}/ca-cert"

bosh -n update-runtime-config "${BOSH_DEPLOYMENT_DIR}/runtime-configs/dns.yml" \
  -e "$(cat "${OUTPUT_DIR}/external-ip")" \
  --client admin \
  --client-secret "${BOSH_CLIENT_SECRET}" \
  --ca-cert "${OUTPUT_DIR}/ca-cert"

director_url="https://$(cat "${OUTPUT_DIR}/external-ip")"
escaped_ca_cert="$(cat ${OUTPUT_DIR}/ca-cert | sed ':a;N;$!ba;s/\n/\\n/g')"

# Adding https: escapes the regex that would otherwise convert to sslip
echo ${director_url} > "${OUTPUT_DIR}/director-url"

# Replacing newlines with \n is hard apparently
# https://stackoverflow.com/questions/1251999/how-can-i-replace-a-newline-n-using-sed
cat <<HEREDOC > "${OUTPUT_DIR}/bosh-deployment-resource-source-file"
{
  client: "admin",
  client_secret: "${BOSH_CLIENT_SECRET}",
  target: "${director_url}",
  ca_cert: "${escaped_ca_cert}"
}
HEREDOC

# Create a bbl state file with credentials so that scripts can target the director with `bbl print-env`
cat <<HEREDOC > "${OUTPUT_DIR}/bbl-state.json"
{
  "version": 3,
  "bosh": {
    "directorUsername": "admin",
    "directorPassword": "${BOSH_CLIENT_SECRET}",
    "directorAddress": "${director_url}",
    "directorSSLCA": "${escaped_ca_cert}"
  }
}
HEREDOC

# Create a file which can be sourced in order to get all the env vars to talk to the bosh director
cat <<HEREDOC > "${OUTPUT_DIR}/source_me"
#!/usr/bin/env bash

bosh_lite_info_dir="\$( cd "\$( dirname "\${BASH_SOURCE[0]}" )" && pwd )"

export BOSH_ENVIRONMENT=$(cat "${OUTPUT_DIR}/external-ip")
export BOSH_CA_CERT=\${bosh_lite_info_dir}/ca-cert
export BOSH_CLIENT=admin
export BOSH_CLIENT_SECRET=${BOSH_CLIENT_SECRET}
export BOSH_GW_PRIVATE_KEY=\${bosh_lite_info_dir}/jumpbox-private-key
HEREDOC
