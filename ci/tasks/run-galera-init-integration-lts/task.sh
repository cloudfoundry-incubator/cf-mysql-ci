#!/bin/bash
set -euo pipefail

trap "killall --signal KILL mysqld; service docker stop" EXIT

service docker start

while ! docker info > /dev/null; do
  sleep 2
done

echo "Pulling docker image: percona/percona-xtradb-cluster:5.7"
time docker pull percona/percona-xtradb-cluster:5.7

cat > /tmp/init.sql <<EOF
CREATE USER 'root'@'127.0.0.1';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'127.0.0.1' WITH GRANT OPTION;
EOF

mysqld --initialize-insecure \
       --init-file=/tmp/init.sql > mysqld_initialize.log 2>&1
mysqld --character-set-server=utf8 \
       --collation-server=utf8_unicode_ci \
       --daemonize \
       --log-error=/tmp/mysqld.log

if [[ ! -d /sys/fs/cgroup/systemd ]]; then
    # Fix for issue where container creation fails: https://github.com/moby/moby/issues/36016
    mkdir /sys/fs/cgroup/systemd
    mount -t cgroup -o none,name=systemd cgroup /sys/fs/cgroup/systemd
fi

pushd pxc-release
    source .envrc
    ginkgo -r -slowSpecThreshold=180 \
           -race \
           -failOnPending \
           -randomizeAllSpecs \
           src/github.com/cloudfoundry/galera-init/integration_test/
popd
