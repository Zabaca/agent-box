# Agent Box

A sandboxed VM environment that gives Claude Code full sudo access on macOS Apple Silicon.

## Why?

Claude Code is powerful but constrained on your host machine - it can't install system packages, run Docker containers freely, or modify system configurations without risking your environment.

Agent Box solves this by giving Claude Code its own Linux VM with:
- **Full sudo access** - install anything, modify system files, no restrictions
- **Isolated environment** - mistakes don't affect your Mac
- **Native filesystem performance** - fast I/O for all operations
- **Observable workspace** - you can watch and collaborate via SSHFS mount

Think of it as a sandbox where Claude Code can work autonomously while you observe.

## Architecture

```
┌─────────────────────────────────────────────┐
│  VM (Claude Code workspace)                 │
│  /agent-workspace  ← native ext4 filesystem │
│  - fast file I/O                            │
│  - full sudo, Docker, Node.js, etc.         │
└──────────────────┬──────────────────────────┘
                   │ SSHFS (host mounts guest)
                   ▼
┌─────────────────────────────────────────────┐
│  Your Mac                                   │
│  ~/vm-workspace  ← observe/collaborate      │
└─────────────────────────────────────────────┘
```

## Prerequisites

```bash
brew install lima
brew install macfuse
brew install gromgit/fuse/sshfs-mac
```

> **Note:** macFUSE requires kernel extension approval. See [MACFUSE.md](MACFUSE.md).

## Usage

```bash
./vm.sh start   # Creates VM, provisions, auto-mounts ~/vm-workspace
./vm.sh ssh     # Access the VM
./vm.sh stop    # Stop VM (auto-unmounts)
./vm.sh destroy # Delete VM
```

First boot takes a few minutes (downloads Ubuntu image and provisions).

### Other Commands

```bash
./vm.sh status   # Show VM and mount status
./vm.sh mount    # Mount workspace only
./vm.sh unmount  # Unmount workspace only
```

### View VM Files from Mac

After starting, the VM's workspace is mounted at:
```
~/vm-workspace
```

## What's Installed in the VM

- Ubuntu 24.04 (ARM64)
- Docker
- Node.js + npm
- Git
- Claude Code CLI

## Why Not Traditional Shared Folders?

NFS and VirtFS/9P have performance issues or don't work well with UTM. The reverse mount approach (host mounts into VM via SSHFS) gives Claude Code native filesystem speed while still allowing you to observe.

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

## License

MIT
