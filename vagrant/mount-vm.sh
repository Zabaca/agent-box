#!/bin/bash
set -e

MOUNT_PATH="$1"
IDENTITY_FILE="$2"

mkdir -p "$MOUNT_PATH"

if mount | grep -q "$MOUNT_PATH"; then
  echo "Already mounted"
else
  sshfs vagrant@127.0.0.1:/agent-workspace "$MOUNT_PATH" -p 2222 \
    -o IdentityFile="$IDENTITY_FILE",StrictHostKeyChecking=no,UserKnownHostsFile=/dev/null,reconnect,ServerAliveInterval=15
  echo "Mounted successfully"
fi
