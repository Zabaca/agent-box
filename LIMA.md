# Lima Setup

A VM environment for Claude Code using Lima on macOS Apple Silicon.

## Prerequisites

### 1. Install Lima

```bash
brew install lima
```

### 2. Install macFUSE and SSHFS (for host mounting)

```bash
brew install macfuse
brew install gromgit/fuse/sshfs-mac
```

**Important:** macFUSE requires kernel extension approval on Apple Silicon Macs. This involves booting into Recovery Mode. See **[MACFUSE.md](MACFUSE.md)** for the complete setup guide.

## Getting Started

### Create the VM config

Create `claude-vm.yaml`:

```yaml
images:
  - location: "https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-arm64.img"
    arch: "aarch64"

cpus: 2
memory: "4GiB"
disk: "20GiB"

# Disable default host→guest mounts (we do the reverse)
mounts: []

provision:
  - mode: system
    script: |
      #!/bin/bash
      set -eux
      export DEBIAN_FRONTEND=noninteractive

      apt-get update
      apt-get install -y docker.io nodejs npm git unzip
      npm install -g @anthropic-ai/claude-code --no-audit

      mkdir -p /agent-workspace
      usermod -aG docker ${LIMA_CIDATA_USER}
      chown -R ${LIMA_CIDATA_USER}:${LIMA_CIDATA_USER} /agent-workspace
```

### Start the VM

```bash
limactl start claude-vm.yaml
```

First boot takes a few minutes (downloads Ubuntu image and provisions).

### Access the VM

```bash
lima
```

Or explicitly:
```bash
limactl shell claude-vm
```

You'll be logged in with full sudo access. Work in `/agent-workspace`.

### Mount VM workspace to your Mac

```bash
mkdir -p ~/vm-workspace
sshfs -F <(limactl show-ssh --format config claude-vm) lima-claude-vm:/agent-workspace ~/vm-workspace -o reconnect,ServerAliveInterval=15
```

### Unmount

```bash
umount ~/vm-workspace
```

### Stop the VM

```bash
limactl stop claude-vm
```

### Delete the VM

```bash
limactl delete claude-vm
```

## Helper Script

Create `vm.sh` for convenience:

```bash
#!/bin/bash
set -e

VM_NAME="claude-vm"
MOUNT_PATH="$HOME/vm-workspace"

case "${1:-}" in
  start)
    limactl start $VM_NAME 2>/dev/null || limactl start claude-vm.yaml
    mkdir -p "$MOUNT_PATH"
    if ! mount | grep -q "$MOUNT_PATH"; then
      sshfs -F <(limactl show-ssh --format config $VM_NAME) lima-$VM_NAME:/agent-workspace "$MOUNT_PATH" -o reconnect,ServerAliveInterval=15
      echo "Mounted to $MOUNT_PATH"
    fi
    ;;
  stop)
    umount "$MOUNT_PATH" 2>/dev/null || true
    limactl stop $VM_NAME
    ;;
  ssh)
    limactl shell $VM_NAME
    ;;
  destroy)
    umount "$MOUNT_PATH" 2>/dev/null || true
    limactl delete $VM_NAME -f
    ;;
  status)
    limactl list
    ;;
  *)
    echo "Usage: $0 {start|stop|ssh|destroy|status}"
    exit 1
    ;;
esac
```

Make it executable:
```bash
chmod +x vm.sh
```

Usage:
```bash
./vm.sh start    # Start VM and mount workspace
./vm.sh ssh      # Enter the VM
./vm.sh stop     # Unmount and stop VM
./vm.sh destroy  # Delete VM completely
./vm.sh status   # Show VM status
```

## Architecture

```
┌─────────────────────────────────────────────┐
│  Lima VM (Claude Code workspace)            │
│  /agent-workspace  ← native ext4 filesystem │
│  - fast file I/O                            │
│  - full sudo access                         │
└──────────────────┬──────────────────────────┘
                   │ SSHFS (host mounts guest)
                   ▼
┌─────────────────────────────────────────────┐
│  Your Mac                                   │
│  ~/vm-workspace  ← observe/collaborate      │
└─────────────────────────────────────────────┘
```

## Troubleshooting

### VM fails to start

Check logs:
```bash
limactl logs claude-vm
```

### SSHFS mount fails / "file system is not available"

The macFUSE kernel extension isn't loaded. Check:
```bash
kextstat | grep macfuse
```

If empty, follow the complete setup in **[MACFUSE.md](MACFUSE.md)**.

### SSHFS mount fails (other errors)

Test SSH connectivity first:
```bash
limactl shell claude-vm
```

If that works, check SSHFS config:
```bash
limactl show-ssh --format config claude-vm
```

### DNS issues on corporate VPN

Lima sometimes has DNS problems on VPNs. Add to your `claude-vm.yaml`:

```yaml
dns:
  - 8.8.8.8
  - 8.8.4.4
```

## Lima vs Vagrant

| Aspect | Lima | Vagrant + UTM |
|--------|------|---------------|
| Setup complexity | Simpler | More moving parts |
| Plugin issues | None | vagrant-utm quirks |
| Config format | YAML | Ruby DSL |
| Triggers/hooks | Manual script | Built-in |
| Multi-provider | No | Yes (not needed here) |

For this use case, Lima is recommended due to simpler setup and fewer compatibility issues.
