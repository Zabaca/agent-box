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

## Setup Options

| Option | Complexity | Recommended |
|--------|------------|-------------|
| [Vagrant + UTM](vagrant/VAGRANT.md) | More setup, but automated triggers | ✓ |
| [Lima](LIMA.md) | Simpler, manual mount script | |

Both require [macFUSE setup](MACFUSE.md) for the SSHFS host mount.

## Quick Start (Vagrant)

### Prerequisites

```bash
brew install --cask utm
brew install vagrant
vagrant plugin install vagrant_utm
brew install macfuse
brew install gromgit/fuse/sshfs-mac
```

> **Note:** macFUSE requires kernel extension approval. See [MACFUSE.md](MACFUSE.md).

### Usage

```bash
cd vagrant
vagrant up      # Creates VM, provisions, auto-mounts ~/vm-workspace
vagrant ssh     # Access the VM
vagrant halt    # Stop VM (auto-unmounts)
vagrant destroy # Delete VM
```

## What's Installed in the VM

- Ubuntu 24.04 (ARM64)
- Docker
- Node.js + npm
- Git
- Claude Code CLI

## Why Not Traditional Shared Folders?

NFS and VirtFS/9P have performance issues or don't work well with UTM. The reverse mount approach (host mounts into VM via SSHFS) gives Claude Code native filesystem speed while still allowing you to observe.

## License

MIT
