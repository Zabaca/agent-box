# Vagrant + UTM Setup

A VM environment for Claude Code using Vagrant with the UTM provider on macOS Apple Silicon.

## Prerequisites

### 1. Install UTM (Homebrew version required)

The App Store version doesn't include `utmctl`. You must use the Homebrew version:

```bash
# If you have the App Store version, remove it first
brew install --cask utm
```

Verify `utmctl` is available:
```bash
utmctl list
```

### 2. Install Vagrant

```bash
brew install vagrant
```

### 3. Install vagrant-utm plugin

```bash
vagrant plugin install vagrant_utm
```

### 4. Install macFUSE and SSHFS (for host mounting)

```bash
brew install macfuse
brew install gromgit/fuse/sshfs-mac
```

**Important:** macFUSE requires kernel extension approval on Apple Silicon Macs. This involves booting into Recovery Mode. See **[MACFUSE.md](../MACFUSE.md)** for the complete setup guide.

### 5. Grant Automation Permission

Your terminal app needs permission to control UTM:
1. Open **System Settings → Privacy & Security → Automation**
2. Find your terminal app (Terminal, iTerm, Ghostty, etc.)
3. Enable the toggle for **UTM**

## Getting Started

### Start the VM

```bash
cd /path/to/this/directory
vagrant up
```

This will:
- Create and boot the VM in UTM
- Provision it with Docker, Node.js, npm, git, and Claude Code
- Mount the VM's `/agent-workspace` to `~/vm-workspace` on your Mac

### Access the VM

```bash
vagrant ssh
```

You'll be logged in as `vagrant` with full sudo access. Work in `/agent-workspace`.

### View VM Files from Mac

After `vagrant up`, the VM's workspace is mounted at:
```
~/vm-workspace
```

### Stop the VM

```bash
vagrant halt
```

This automatically unmounts `~/vm-workspace`.

### Destroy the VM

```bash
vagrant destroy -f
```

## Troubleshooting

### "OSStatus error -1712"

UTM automation permission issue:
1. Quit UTM completely (Cmd+Q)
2. Quit your terminal
3. Reopen UTM first, then your terminal
4. Try again

### VM won't start / hangs on "Booting VM"

```bash
# Check if UTM can control the VM directly
utmctl list
utmctl start <vm-name>
```

If `utmctl` also fails, quit and restart UTM.

### SSHFS mount fails / "file system is not available"

The macFUSE kernel extension isn't loaded. Check:
```bash
kextstat | grep macfuse
```

If empty, follow the complete setup in **[MACFUSE.md](../MACFUSE.md)**.

To test manually:
```bash
sshfs -p 2222 vagrant@127.0.0.1:/agent-workspace ~/vm-workspace \
  -o IdentityFile=.vagrant/machines/default/utm/private_key \
  -o StrictHostKeyChecking=no
```

## Architecture

```
┌─────────────────────────────────────────────┐
│  VM (Claude Code workspace)                 │
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

The VM has native filesystem performance. Your Mac mounts into it via SSHFS for observation.

## Project Files

| File | Purpose |
|------|---------|
| `Vagrantfile` | VM configuration and triggers |
| `mount-vm.sh` | Auto-mount script (called by trigger) |
| `unmount-vm.sh` | Auto-unmount script (called by trigger) |

## Limitations

- NFS shared folders don't work with vagrant-utm
- VirtFS (9P) has poor performance
- UTM sometimes needs a full restart after permission changes
