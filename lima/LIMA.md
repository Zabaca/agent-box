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

**Important:** macFUSE requires kernel extension approval on Apple Silicon Macs. This involves booting into Recovery Mode. See **[MACFUSE.md](../MACFUSE.md)** for the complete setup guide.

## Getting Started

### Start the VM

```bash
cd lima
./vm.sh start
```

First boot takes a few minutes (downloads Ubuntu image and provisions).

This will:
- Create and boot the VM
- Provision it with Docker, Node.js, npm, git, and Claude Code
- Mount the VM's `/agent-workspace` to `~/vm-workspace` on your Mac

### Access the VM

```bash
./vm.sh ssh
```

You'll be logged in with full sudo access. Work in `/agent-workspace`.

### View VM Files from Mac

After starting, the VM's workspace is mounted at:
```
~/vm-workspace
```

### Stop the VM

```bash
./vm.sh stop
```

This automatically unmounts `~/vm-workspace`.

### Other Commands

```bash
./vm.sh status   # Show VM and mount status
./vm.sh mount    # Mount workspace only
./vm.sh unmount  # Unmount workspace only
./vm.sh destroy  # Delete VM completely
```

## Project Files

| File | Purpose |
|------|---------|
| `claude-vm.yaml` | Lima VM configuration |
| `vm.sh` | Helper script for start/stop/mount |

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

If empty, follow the complete setup in **[MACFUSE.md](../MACFUSE.md)**.

### SSHFS mount fails (other errors)

Test SSH connectivity first:
```bash
./vm.sh ssh
```

If that works, check SSHFS config:
```bash
limactl show-ssh --format config claude-vm
```

### DNS issues on corporate VPN

Lima sometimes has DNS problems on VPNs. Add to `claude-vm.yaml`:

```yaml
dns:
  - 8.8.8.8
  - 8.8.4.4
```
