#!/bin/bash
set -eux

BBL_GIT_TAG=`cat bbl-github-release/tag`
BBL6_GIT_TAG="v6.10.44"
BOSH_CLI_VERSION=`cat bosh-cli-github-release/version`
CREDHUB_CLI_VERSION=`cat credhub-cli-github-release/version`
TERRAFORM_VERSION=`cat terraform-github-release/version | tr -d v`

cat << EOF > docker-build-args/docker-build-args.json
{
  "BBL_GIT_TAG": "${BBL_GIT_TAG}",
  "BBL6_GIT_TAG": "${BBL6_GIT_TAG}",
  "BOSH_CLI_VERSION": "${BOSH_CLI_VERSION}",
  "CREDHUB_CLI_VERSION": "${CREDHUB_CLI_VERSION}",
  "TERRAFORM_VERSION": "${TERRAFORM_VERSION}"
}
EOF
