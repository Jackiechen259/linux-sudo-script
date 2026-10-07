#!/usr/bin/env bash
set -Eeuo pipefail

# linux-sudo-script
# Install sudo when missing and grant sudo access to the user running this script.
#
# One-line usage:
#   bash <(curl -fsSL https://raw.githubusercontent.com/Jackiechen259/linux-sudo-script/main/enable-sudo.sh)

info()  { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
ok()    { printf '\033[1;32m[ OK ]\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
error() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; }

TARGET_USER="${SUDO_USER:-$(id -un)}"

if [[ ! "$TARGET_USER" =~ ^[a-zA-Z_][a-zA-Z0-9_.-]*$ ]]; then
    error "Unsupported username: $TARGET_USER"
    exit 1
fi

ROOT_HELPER="$(mktemp)"
trap 'rm -f "$ROOT_HELPER"' EXIT

cat > "$ROOT_HELPER" <<'ROOT_SCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail

TARGET_USER="$1"

if [[ "$(id -u)" -ne 0 ]]; then
    echo "[ERROR] Root privileges are required."
    exit 1
fi

if ! id "$TARGET_USER" >/dev/null 2>&1; then
    echo "[ERROR] User does not exist: $TARGET_USER"
    exit 1
fi

echo "[INFO] Target user: $TARGET_USER"

install_sudo() {
    if command -v apt-get >/dev/null 2>&1; then
        echo "[INFO] Installing sudo with apt-get..."
        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y sudo
    elif command -v dnf >/dev/null 2>&1; then
        echo "[INFO] Installing sudo with dnf..."
        dnf install -y sudo
    elif command -v yum >/dev/null 2>&1; then
        echo "[INFO] Installing sudo with yum..."
        yum install -y sudo
    elif command -v zypper >/dev/null 2>&1; then
        echo "[INFO] Installing sudo with zypper..."
        zypper --non-interactive install sudo
    elif command -v pacman >/dev/null 2>&1; then
        echo "[INFO] Installing sudo with pacman..."
        pacman -Sy --needed --noconfirm sudo
    elif command -v apk >/dev/null 2>&1; then
        echo "[INFO] Installing sudo with apk..."
        apk add sudo
    else
        echo "[ERROR] No supported package manager was found."
        exit 1
    fi
}

if command -v sudo >/dev/null 2>&1; then
    echo "[ OK ] sudo is already installed."
else
    echo "[INFO] sudo is not installed."
    install_sudo
fi

if ! command -v sudo >/dev/null 2>&1; then
    echo "[ERROR] sudo installation failed."
    exit 1
fi

VISUDO="$(command -v visudo || true)"
if [[ -z "$VISUDO" ]]; then
    echo "[ERROR] visudo was not found after installing sudo."
    exit 1
fi

mkdir -p /etc/sudoers.d
chmod 0750 /etc/sudoers.d

SAFE_USER="${TARGET_USER//./_}"
SUDOERS_FILE="/etc/sudoers.d/99-user-${SAFE_USER}"
TMP_SUDOERS="$(mktemp)"
trap 'rm -f "$TMP_SUDOERS"' EXIT

# Normal sudo access. The user will still be asked for their own password
# when using sudo; this script does not configure NOPASSWD.
printf '%s ALL=(ALL:ALL) ALL\n' "$TARGET_USER" > "$TMP_SUDOERS"
chmod 0440 "$TMP_SUDOERS"

if ! "$VISUDO" -cf "$TMP_SUDOERS" >/dev/null; then
    echo "[ERROR] Generated sudoers entry is invalid."
    exit 1
fi

install -o root -g root -m 0440 "$TMP_SUDOERS" "$SUDOERS_FILE"

# sudo packages normally include /etc/sudoers.d already. Add the directive
# only on systems where it is missing.
if ! grep -Eq '^[[:space:]]*(@|#)includedir[[:space:]]+/etc/sudoers\.d([[:space:]]|$)' /etc/sudoers; then
    BACKUP="/etc/sudoers.backup.$(date +%Y%m%d-%H%M%S)"
    echo "[INFO] Backing up /etc/sudoers to $BACKUP"
    cp -a /etc/sudoers "$BACKUP"
    printf '\n@includedir /etc/sudoers.d\n' >> /etc/sudoers
fi

if ! "$VISUDO" -cf /etc/sudoers >/dev/null; then
    echo "[ERROR] Final sudoers validation failed."
    exit 1
fi

echo
echo "[ OK ] sudo is installed and configured."
echo "[ OK ] User '$TARGET_USER' has sudo access."
echo "[INFO] sudoers entry: $SUDOERS_FILE"
ROOT_SCRIPT

chmod 700 "$ROOT_HELPER"

echo
info "Current account: $TARGET_USER"

if [[ "$(id -u)" -eq 0 ]]; then
    info "Already running as root."
    /bin/bash "$ROOT_HELPER" "$TARGET_USER"
else
    USED_SUDO=false

    # If sudo already exists and this account can authenticate with it,
    # use it. Otherwise fall back to su/root password.
    if command -v sudo >/dev/null 2>&1; then
        info "sudo is installed. Checking whether this account can use it..."
        if sudo -v; then
            sudo /bin/bash "$ROOT_HELPER" "$TARGET_USER"
            USED_SUDO=true
        else
            warn "Current account could not authenticate with sudo."
        fi
    fi

    if [[ "$USED_SUDO" != true ]]; then
        if ! command -v su >/dev/null 2>&1; then
            error "'su' is not available and sudo could not be used."
            exit 1
        fi

        echo
        info "Root privileges are required."
        info "Enter the root (su) password when prompted."
        echo

        # su/PAM reads the root password interactively from the terminal.
        su -c "/bin/bash '$ROOT_HELPER' '$TARGET_USER'"
    fi
fi

echo
ok "Finished."
echo
echo "Test sudo with:"
echo "  sudo whoami"
echo
echo "Expected output:"
echo "  root"
