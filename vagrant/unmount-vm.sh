#!/bin/bash

MOUNT_PATH="$1"

if mount | grep -q "$MOUNT_PATH"; then
  diskutil unmount force "$MOUNT_PATH" 2>/dev/null || umount -f "$MOUNT_PATH" 2>/dev/null || true
  echo "Unmounted"
else
  echo "Not mounted"
fi

exit 0
