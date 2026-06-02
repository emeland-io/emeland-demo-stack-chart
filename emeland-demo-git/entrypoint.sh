#!/bin/sh
set -eu

# authorized_keys is mounted from Kubernetes Secret at runtime
mkdir -p /home/git/.ssh
chmod 700 /home/git/.ssh
chown -R git:git /home/git/.ssh

if [ -f /home/git/.ssh/authorized_keys ]; then
  chmod 600 /home/git/.ssh/authorized_keys
  chown git:git /home/git/.ssh/authorized_keys
fi

mkdir -p /var/run
exec "$@"
