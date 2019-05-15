#!/bin/bash

set -eux

WORKSPACE_DIR="$(pwd)"

# Params
: "${RELEASE_NAME:?}"
FINAL=${FINAL:-}
SHA2=${SHA2:-}
PRIVATE_YAML=${PRIVATE_YAML:-}
AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-}"
AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-}"
BLOBS_BUCKET_NAME="${BLOBS_BUCKET_NAME:-}"

# Inputs
release_repo="${WORKSPACE_DIR}/release-repo"

# Outputs
release_repo_modified="${WORKSPACE_DIR}/release-repo-modified"
tarball_dir="${WORKSPACE_DIR}/release-tarball"

# First argument should be path to file
function write_private_yaml() {
  cat <<EOF > $1
---
blobstore:
  provider: s3
  options:
    bucket_name: ${BLOBS_BUCKET_NAME}
    access_key_id: ${AWS_ACCESS_KEY_ID}
    secret_access_key: ${AWS_SECRET_ACCESS_KEY}
EOF
}

function check_for_untested_commits() {
    eval "$(ssh-agent -s)"
    github_ssh_key=/tmp/git.rsa
    echo "$GITHUB_SSH_KEY" > $github_ssh_key
    chmod 0600 $github_ssh_key
    ssh-add $github_ssh_key
    pushd $release_repo
        git fetch >/dev/null
        if [[ -n $(git diff origin/master) ]]; then
            echo "Untested commits still in the pipeline, exiting without cutting final..."
            exit 1
        fi
    popd
}

create_release_command="bosh -n create-release --name ${RELEASE_NAME} --force"

tarball_path="${tarball_dir}/${RELEASE_NAME}-dev.tgz"

if [ -n "${FINAL}" ]; then
  create_release_command="${create_release_command} --final"
  check_for_untested_commits
else
  mkdir -p "${release_repo_modified}"
fi

if [ -n "${SHA2}" ]; then
  export BOSH_SHA2=true
fi

if [ -e "${WORKSPACE_DIR}/version/version" ]; then
  version=$(cat ${WORKSPACE_DIR}/version/version)
  echo "Final release ${version}" > commit-message/commit-message

  tarball_path="${tarball_dir}/${RELEASE_NAME}-${version}.tgz"

  create_release_command="${create_release_command} --version ${version}"
else
  create_release_command="${create_release_command} --timestamp-version"
fi

create_release_command="${create_release_command} --tarball ${tarball_path}"

# copy all files, including hidden (e.g. .git/)
shopt -s dotglob

cp -r "${release_repo}"/* "${release_repo_modified}"

pushd "${release_repo_modified}"
    if [[ -n "${AWS_ACCESS_KEY_ID}" && -n "${AWS_SECRET_ACCESS_KEY}" && -n "${BLOBS_BUCKET_NAME}" ]]; then
      write_private_yaml "${PWD}/config/private.yml"
    fi
    if [[ -n "${PRIVATE_YAML}" ]]; then
      echo "${PRIVATE_YAML}" > "${PWD}/config/private.yml"
    fi

    set +e
    create_release_output=$(${create_release_command} 2>&1)
    create_release_exit_code=$?
    set -e

    if [ "${create_release_exit_code}" -ne 0 ]; then
      # retry on blobstore error, else exit

      # turn off trace to avoid printing output twice
      set +x
      if [[ "${create_release_output}" == *"Blobstore error"* ]]; then
        set -x
        ${create_release_command}
      else
        set -x
        exit "${create_release_exit_code}"
      fi
    fi
popd
