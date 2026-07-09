# WSL Distro Management Guide

This guide shows how to:
- Find available WSL distros
- Install (add) a distro
- Remove (delete) a distro

All commands below are for Windows PowerShell.

## 1) Install WSL2 (First-Time Setup)

If you have never set up WSL, do this first.

### Recommended path (Windows 11, or newer Windows 10 builds)

Open PowerShell as Administrator and run:

```powershell
wsl --install
```

This installs:
- WSL platform
- Virtual Machine Platform feature
- Linux kernel components
- Default Linux distro (typically Ubuntu)

Reboot if prompted. After reboot, verify:

```powershell
wsl --status
wsl --version
```

Ensure default version is WSL2:

```powershell
wsl --set-default-version 2
```

### Fallback path (if `wsl --install` is unavailable)

Run in elevated PowerShell:

```powershell
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
```

Reboot, then update WSL and set WSL2 default:

```powershell
wsl --update
wsl --set-default-version 2
```

If needed, install a distro after this:

```powershell
wsl --install -d Ubuntu-24.04
```

### BIOS/UEFI note (if WSL2 fails to start)

WSL2 requires CPU virtualization support enabled in BIOS/UEFI (Intel VT-x or AMD-V).

## 2) Prerequisites / Health Check

Run these in an elevated PowerShell window (Run as Administrator) if WSL is not already set up.

```powershell
wsl --status
```

If WSL is not installed:

```powershell
wsl --install
```

Reboot if prompted.

## 3) Find Distros

### List distro names available for install

```powershell
wsl --list --online
# short form
wsl -l -o
```

### List distros currently installed on your machine

```powershell
wsl --list --verbose
# short form
wsl -l -v
```

### See the default distro and WSL version details

```powershell
wsl --status
```

## 4) Install (Add) a Distro

### Install a distro from the online catalog

Use a name from `wsl -l -o`.

```powershell
wsl --install -d Ubuntu-24.04
```

Example alternatives:

```powershell
wsl --install -d Debian
wsl --install -d openSUSE-Tumbleweed
```

After install, launch it:

```powershell
wsl -d Ubuntu-24.04
```

### Install and add a Windows Terminal profile in one step

Use the standalone script from this repo when you want the distro installed, started, and added as a Windows Terminal profile:

```powershell
./scripts/install-wsl-distro-and-terminal-profile.ps1 -d Ubuntu-24.04
```

The script backs up each Windows Terminal `settings.json` file it updates and reuses the profile if it already exists.

### Set default WSL version for new installs (recommended)

```powershell
wsl --set-default-version 2
```

### Set your default distro

```powershell
wsl --set-default Ubuntu-24.04
```

Verify:

```powershell
wsl -l -v
```

## 5) Start (Launch) a Distro

### Start your default distro

```powershell
wsl
```

### Start a specific distro by name

```powershell
wsl -d Ubuntu-24.04
```

### Start from Command Prompt (CMD)

```cmd
wsl
wsl -d Ubuntu-24.04
```

### Start from Windows Terminal

- Open Windows Terminal and select your Linux profile (for example, Ubuntu-24.04).
- Or open a PowerShell tab and run `wsl` or `wsl -d <DistroName>`.

### Confirm it started

```powershell
wsl -l -v
```

`STATE` should show `Running` for the distro you launched.

## 6) Stop or Restart Distros

### Stop one distro

```powershell
wsl --terminate Ubuntu-24.04
```

### Stop all running distros and WSL VM

```powershell
wsl --shutdown
```

## 7) Delete (Remove) a Distro

Deleting a distro is destructive and removes its filesystem/data.

### Optional but recommended: backup first

```powershell
wsl --export Ubuntu-24.04 C:\Backups\Ubuntu-24.04.tar
```

### Delete (unregister) the distro

```powershell
wsl --unregister Ubuntu-24.04
```

### Confirm deletion

```powershell
wsl -l -v
```

## 8) Restore a Deleted Distro from Backup (Optional)

If you exported a `.tar`, you can import it back.

```powershell
wsl --import Ubuntu-24.04-Restored C:\WSL\Ubuntu-24.04-Restored C:\Backups\Ubuntu-24.04.tar --version 2
```

Then launch it:

```powershell
wsl -d Ubuntu-24.04-Restored
```

## 9) Common Troubleshooting

### Error: distro name not found

- Re-run `wsl -l -o` and copy exact distro name.

### Error: WSL command not recognized

- Update Windows and run `wsl --install` in elevated PowerShell.
- Reboot and try again.

### Need latest WSL engine

```powershell
wsl --update
```

Check version:

```powershell
wsl --version
```

## Quick Command Reference

```powershell
# Discover
wsl -l -o
wsl -l -v

# Install
wsl --install -d <DistroName>

# Set defaults
wsl --set-default-version 2
wsl --set-default <DistroName>

# Stop
wsl --terminate <DistroName>
wsl --shutdown

# Backup and delete
wsl --export <DistroName> C:\Backups\<DistroName>.tar
wsl --unregister <DistroName>

# Restore
wsl --import <NewName> C:\WSL\<NewName> C:\Backups\<DistroName>.tar --version 2
```