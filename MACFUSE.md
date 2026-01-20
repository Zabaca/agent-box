# macFUSE Setup on Apple Silicon Macs

macFUSE is required for SSHFS to mount remote filesystems on macOS. Apple Silicon Macs have stricter security requirements that need to be configured before macFUSE can work.

## Overview

The setup requires:
1. Install macFUSE and SSHFS
2. Boot into Recovery Mode to change security policy
3. Allow the kernel extension in System Settings
4. Restart to load the extension

**Total time:** ~10-15 minutes (including restarts)

## Step 1: Install macFUSE and SSHFS

```bash
brew install macfuse
brew install gromgit/fuse/sshfs-mac
```

## Step 2: Attempt First Use (Will Fail)

Try using SSHFS - it will fail but triggers macOS to recognize the extension:

```bash
sshfs user@host:/path ~/mountpoint
# Error: mount_macfuse: the file system is not available (1)
```

## Step 3: Allow in System Settings

1. Open **System Settings**
2. Go to **Privacy & Security**
3. Scroll down to the **Security** section
4. You'll see: *"System software from developer 'Benjamin Fleischer' was blocked"*
5. Click **Allow**

A dialog will appear saying you need to modify security settings in Recovery Mode.

## Step 4: Boot into Recovery Mode

1. Click **Shut Down** (or shut down your Mac)
2. Press and **hold the power button** until you see "Loading startup options"
3. Select **Options** and click **Continue**
4. If prompted, select your user and enter your password

## Step 5: Change Security Policy

1. In the menu bar, click **Utilities → Startup Security Utility**
2. Select your startup disk (usually "Macintosh HD")
3. Click **Security Policy...**
4. Select **Reduced Security**
5. Check **"Allow user management of kernel extensions from identified developers"**
6. Click **OK**
7. Enter your password if prompted
8. Click **Restart** from the Apple menu

## Step 6: Allow the Extension Again

After restarting:

1. Open **System Settings → Privacy & Security**
2. Scroll to **Security** section
3. You should see the macFUSE extension waiting for approval
4. Click **Allow**
5. You'll see: *"New system extensions require a restart before they can be used"*
6. Click **Restart**

## Step 7: Verify Installation

After the final restart:

```bash
# Check if macFUSE kernel extension is loaded
kextstat | grep macfuse

# Should show something like:
# xxx  0 0xffffff... 0x...  io.macfuse.filesystems.macfuse (...)

# Test SSHFS
mkdir -p ~/test-mount
sshfs user@host:/path ~/test-mount
ls ~/test-mount

# Unmount when done
umount ~/test-mount
```

## Troubleshooting

### "the file system is not available" error

The kernel extension isn't loaded. Verify:

```bash
kextstat | grep -i fuse
```

If empty, you need to complete the Recovery Mode steps above.

### Extension not appearing in Privacy & Security

Try reinstalling macFUSE:

```bash
brew uninstall macfuse
brew install macfuse
```

Then attempt to use SSHFS again to trigger the approval dialog.

### Recovery Mode won't boot

1. Fully shut down (don't restart)
2. Wait 10 seconds
3. Press and hold power button until you see "Loading startup options"

### "Reduced Security" concerns

Reduced Security only allows **identified developer** kernel extensions (signed and notarized by Apple). It does not disable other security features like:
- System Integrity Protection (SIP)
- Secure Boot
- FileVault encryption

macFUSE is signed by an identified developer (Benjamin Fleischer) and is widely used.

## Uninstalling macFUSE

If you no longer need macFUSE:

```bash
brew uninstall sshfs-mac
brew uninstall macfuse
```

You can also revert to Full Security in Recovery Mode if desired.

## Summary of Restarts

| Step | Action |
|------|--------|
| 1 | Shut down → Recovery Mode (hold power) |
| 2 | Change security policy → Restart |
| 3 | Allow extension → Restart |
| **Done** | macFUSE working |

After completing these steps once, macFUSE will continue to work across future macOS updates (though major updates may occasionally require re-allowing the extension).
