#!/usr/bin/env bash

set -eux

WORKSPACE_DIR="$(pwd)"
REPO_DIR="$(cd "${WORKSPACE_DIR}/${REPO_DIR:?}" && pwd )"

OUTPUT_DIR="${OUTPUT_DIR:?}"
GIT_COMMIT_MESSAGE="${GIT_COMMIT_MESSAGE:?}"

if [ -f "${GIT_COMMIT_MESSAGE}" ]
then
  GIT_COMMIT_MESSAGE=$(cat "${GIT_COMMIT_MESSAGE}")
fi

pushd ${REPO_DIR}

  git config --global user.email "core-services-bot@pivotal.io"
  git config --global user.name "Final Release Builder"

  git add -A .

  if ! git diff-index --quiet HEAD; then
    git commit -m "${GIT_COMMIT_MESSAGE}"
  fi

popd

cp -rf ${REPO_DIR} ${OUTPUT_DIR}
