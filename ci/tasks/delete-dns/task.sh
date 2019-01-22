#!/bin/bash
set -eux

workspace_dir="$(pwd)"
service_key="${workspace_dir}/deployments-core-services/bosh-lite-gcp/ci-service-account.json"

gcloud auth activate-service-account --key-file=${service_key}
gcloud config set project cf-core-services

zone="bosh-lite"

wildcard_url=$(cat "${workspace_dir}/url/wildcard_url")

ip_address=$(cat "${workspace_dir}/bosh-lite-info/external-ip")

gcloud dns record-sets transaction start --zone bosh-lite
gcloud dns record-sets transaction remove --zone bosh-lite --name "${wildcard_url}" --ttl 300 --type A "${ip_address}"
gcloud dns record-sets transaction execute --zone bosh-lite
