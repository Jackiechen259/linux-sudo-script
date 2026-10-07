# linux-sudo-script

A small bootstrap script for Linux systems that makes `sudo` available to the current user.

It is designed primarily for **Debian, Ubuntu, and Proxmox**, while also supporting several other common Linux package managers.

## One-line usage

### curl

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Jackiechen259/linux-sudo-script/main/enable-sudo.sh)
```

### wget

```bash
bash <(wget -qO- https://raw.githubusercontent.com/Jackiechen259/linux-sudo-script/main/enable-sudo.sh)
```

Both versions keep stdin attached to your terminal, so authentication prompts from `sudo` or `su` work normally.

## What it does

1. Detects the normal user account running the script.
2. Checks whether `sudo` is installed.
3. Installs `sudo` when necessary.
4. Tries existing sudo access first.
5. If sudo is unavailable, falls back to `su` and prompts for the root password.
6. Creates a dedicated sudoers entry for the current user.
7. Validates the configuration with `visudo`.

The generated entry is stored under:

```text
/etc/sudoers.d/99-user-<username>
```

and grants normal password-protected sudo access:

```text
<username> ALL=(ALL) ALL
```

This script **does not enable NOPASSWD**.

## Supported package managers

- APT — Debian, Ubuntu, Proxmox
- DNF — Fedora, Rocky Linux, AlmaLinux, newer RHEL-family systems
- YUM
- Zypper — openSUSE
- Pacman — Arch Linux
- APK — Alpine Linux

## Example

Run:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Jackiechen259/linux-sudo-script/main/enable-sudo.sh)
```

If the account does not already have sudo access, you may see:

```text
[INFO] Falling back to su.
[INFO] Enter the root password when prompted.

Password:
```

After completion, test with:

```bash
sudo whoami
```

Expected output:

```text
root
```

## Security notes

- The root password is handled by the system's `su`/PAM authentication prompt.
- The password is not stored in the script.
- The password is not sent to GitHub.
- The script validates sudoers changes using `visudo`.
- If a required `/etc/sudoers` include needs to be added, the original file is backed up first.
- The script does not configure passwordless sudo.

## Re-running the script

The script is intended to be safe to run more than once.

If `sudo` is already installed, it will not reinstall it unnecessarily. The dedicated sudoers entry for the user is replaced with the same validated configuration.

## Remove the granted sudo access

For a user named `jackie`, remove the dedicated entry as root:

```bash
rm -f /etc/sudoers.d/99-user-jackie
visudo -cf /etc/sudoers
```

Replace `jackie` with the actual username.

## Requirements

You need at least one existing path to root privileges:

- working sudo access; or
- a usable root account and its password via `su`.

A Linux system cannot grant new root privileges without an existing root authentication path.

## License

This project is licensed under the [MIT License](LICENSE).

Copyright (c) 2026 Jackie Chen.

## Repository

```text
git@github.com:Jackiechen259/linux-sudo-script.git
```
