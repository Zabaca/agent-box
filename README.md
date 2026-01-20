# Agent Box

A VM environment for running Claude Code on macOS Apple Silicon.

## Overview

This project provides a sandboxed Linux VM where Claude Code can operate with full sudo access and native filesystem performance. Your Mac observes the VM's workspace via SSHFS mount for collaboration.

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

## Why This Architecture?

Traditional shared folders (NFS, VirtFS/9P) have performance issues or don't work well with UTM. Instead:

1. **VM has native filesystem** - Claude Code gets fast I/O
2. **Host mounts into VM** - You observe via SSHFS (speed doesn't matter for observation)
3. **Two-way sync** - Edit from either side

## License

MIT
