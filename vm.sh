#!/bin/bash
set -e

# VM_NAME selects which Lima VM to operate on. Override per command:
#   VM_NAME=ceo-vm ./vm.sh start
# Default = claude-vm (Take 1 archive).
VM_NAME="${VM_NAME:-claude-vm}"

# Host mount path. Defaults to ~/<vm-name>-workspace so multiple VMs don't collide.
# Override if you need a custom layout: MOUNT_PATH=/tmp/foo ./vm.sh start
MOUNT_PATH="${MOUNT_PATH:-$HOME/${VM_NAME}-workspace}"

# Path inside the VM that gets mounted to the host. Set per-VM if your provisioning
# script puts the workspace somewhere other than /agent-workspace.
VM_WORKSPACE="${VM_WORKSPACE:-/agent-workspace}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/${VM_NAME}.yaml"

start_vm() {
  if limactl list -q | grep -q "^${VM_NAME}$"; then
    limactl start "$VM_NAME" 2>/dev/null || true
  else
    if [ ! -f "$CONFIG_FILE" ]; then
      echo "Config not found: $CONFIG_FILE"
      echo "Create ${VM_NAME}.yaml or set VM_NAME to an existing config."
      exit 1
    fi
    limactl start "$CONFIG_FILE" --name="$VM_NAME" --tty=false

    # Restart so any group memberships granted during provisioning take effect.
    echo "Restarting ${VM_NAME} to finalize provisioning..."
    limactl stop "$VM_NAME"
    limactl start "$VM_NAME"
  fi
}

mount_workspace() {
  mkdir -p "$MOUNT_PATH"
  if mount | grep -q "$MOUNT_PATH"; then
    echo "Already mounted at $MOUNT_PATH"
  else
    SSH_CONFIG="$HOME/.lima/$VM_NAME/ssh.config"
    sshfs -F "$SSH_CONFIG" "lima-${VM_NAME}:${VM_WORKSPACE}" "$MOUNT_PATH" \
      -o reconnect,ServerAliveInterval=15
    echo "Mounted ${VM_NAME}:${VM_WORKSPACE} -> ${MOUNT_PATH}"
  fi
}

unmount_workspace() {
  if mount | grep -q "$MOUNT_PATH"; then
    diskutil unmount force "$MOUNT_PATH" 2>/dev/null || umount -f "$MOUNT_PATH" 2>/dev/null || true
    echo "Unmounted ${MOUNT_PATH}"
  else
    echo "Not mounted"
  fi
}

case "${1:-}" in
  start)
    start_vm
    mount_workspace
    ;;
  stop)
    unmount_workspace
    limactl stop "$VM_NAME"
    ;;
  ssh)
    limactl shell "$VM_NAME"
    ;;
  mount)
    mount_workspace
    ;;
  unmount)
    unmount_workspace
    ;;
  destroy)
    unmount_workspace
    limactl delete "$VM_NAME" -f
    ;;
  snapshot)
    TAG="${2:-}"
    if [ -z "$TAG" ]; then
      echo "Usage: $0 snapshot <tag>"
      exit 1
    fi
    limactl snapshot create "$VM_NAME" --tag "$TAG"
    echo "Snapshot '$TAG' created on ${VM_NAME}"
    ;;
  snapshots)
    limactl snapshot list "$VM_NAME"
    ;;
  restore)
    TAG="${2:-}"
    if [ -z "$TAG" ]; then
      echo "Usage: $0 restore <tag>"
      exit 1
    fi
    unmount_workspace
    limactl stop "$VM_NAME" 2>/dev/null || true
    limactl snapshot apply "$VM_NAME" --tag "$TAG"
    echo "Restored ${VM_NAME} to snapshot '$TAG'"
    start_vm
    mount_workspace
    ;;
  delete-snapshot)
    TAG="${2:-}"
    if [ -z "$TAG" ]; then
      echo "Usage: $0 delete-snapshot <tag>"
      exit 1
    fi
    limactl snapshot delete "$VM_NAME" --tag "$TAG"
    echo "Snapshot '$TAG' deleted from ${VM_NAME}"
    ;;
  list)
    limactl list
    ;;
  status)
    echo "VM_NAME=${VM_NAME}"
    echo "MOUNT_PATH=${MOUNT_PATH}"
    echo "VM_WORKSPACE=${VM_WORKSPACE}"
    echo ""
    limactl list "$VM_NAME" 2>/dev/null || echo "VM '${VM_NAME}' not found"
    if mount | grep -q "$MOUNT_PATH"; then
      echo ""
      echo "Mount: $MOUNT_PATH (active)"
    else
      echo ""
      echo "Mount: not mounted"
    fi
    ;;
  *)
    cat <<EOF
Usage: $0 <command> [args]

Selects the VM via the VM_NAME env var (default: claude-vm).
  Example: VM_NAME=ceo-vm $0 start

Commands:
  start              Start VM and mount workspace
  stop               Unmount and stop VM
  ssh                SSH into the VM
  mount              Mount workspace only
  unmount            Unmount workspace only
  destroy            Delete VM completely
  status             Show VM and mount status for current VM_NAME
  list               List all Lima VMs

Snapshots:
  snapshot <tag>          Create a snapshot
  snapshots               List snapshots for current VM_NAME
  restore <tag>           Restore from a snapshot
  delete-snapshot <tag>   Delete a snapshot

Env overrides:
  VM_NAME       which VM to operate on (also picks <name>.yaml config)
  MOUNT_PATH    host mount path (default ~/\${VM_NAME}-workspace)
  VM_WORKSPACE  guest path to mount (default /agent-workspace)
EOF
    exit 1
    ;;
esac
