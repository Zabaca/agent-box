#!/bin/bash
set -e

VM_NAME="claude-vm"
MOUNT_PATH="$HOME/vm-workspace"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

start_vm() {
  if limactl list -q | grep -q "^${VM_NAME}$"; then
    limactl start "$VM_NAME" 2>/dev/null || true
  else
    # First time creation (--tty=false skips interactive prompt)
    limactl start "$SCRIPT_DIR/claude-vm.yaml" --name="$VM_NAME" --tty=false

    # Restart to apply docker group membership
    echo "Restarting VM to apply docker group..."
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
    sshfs -F "$SSH_CONFIG" "lima-${VM_NAME}:/agent-workspace" "$MOUNT_PATH" \
      -o reconnect,ServerAliveInterval=15
    echo "Mounted to $MOUNT_PATH"
  fi
}

unmount_workspace() {
  if mount | grep -q "$MOUNT_PATH"; then
    diskutil unmount force "$MOUNT_PATH" 2>/dev/null || umount -f "$MOUNT_PATH" 2>/dev/null || true
    echo "Unmounted"
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
  status)
    limactl list
    if mount | grep -q "$MOUNT_PATH"; then
      echo ""
      echo "Mount: $MOUNT_PATH (active)"
    else
      echo ""
      echo "Mount: not mounted"
    fi
    ;;
  *)
    echo "Usage: $0 {start|stop|ssh|mount|unmount|destroy|status}"
    echo ""
    echo "Commands:"
    echo "  start    - Start VM and mount workspace"
    echo "  stop     - Unmount and stop VM"
    echo "  ssh      - SSH into the VM"
    echo "  mount    - Mount workspace only"
    echo "  unmount  - Unmount workspace only"
    echo "  destroy  - Delete VM completely"
    echo "  status   - Show VM and mount status"
    exit 1
    ;;
esac
