#!/usr/bin/env bash
set -Eeuo pipefail

# linux-sudo-script
#
# Installs sudo if it is missing and grants full sudo access to the account
# that launched this script.
#
# One-line usage (curl):
#   bash <(curl -fsSL https://raw.githubusercontent.com/Jackiechen259/linux-sudo-script/main/enable-sudo.sh)
#
# One-line usage (wget):
#   bash <(wget -qO- https://raw.githubusercontent.com/Jackiechen259/linux-sudo-script/main/enable-sudo.sh)

info()  { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
ok()    { printf '\033[1;32m[ OK ]\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
error() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; }

TARGET_USER="${SUDO_USER:-$(id -un)}"

if [[ ! "$TARGET_USER" =~ ^[a-zA-Z_][a-zA-Z0-9_.-]*$ ]]; then
    error "Unsupported username: $TARGET_USER"
    exit 1
fi

# Running directly as root gives us no reliable non-root account to grant.
if [[ "$TARGET_USER" == "root" ]]; then
    error "Run this from the normal user account that should receive sudo access."
    error "If sudo already works, you may also run: sudo bash <(curl -fsSL <URL>)"
    exit 1
fi

ROOT_HELPER="$(mktemp)"
trap 'rm -f "$ROOT_HELPER"' EXIT

cat > "$ROOT_HELPER" <<'ROOT_SCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail

TARGET_USER="$1"

# su -c may omit sbin directories from PATH on Debian/Ubuntu/Proxmox.
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

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

install -d -o root -g root -m 0750 /etc/sudoers.d

# Ensure /etc/sudoers.d is active. Debian/Ubuntu/Proxmox already ship this,
# but this also handles minimal images where the include is missing.
if ! grep -Eq '^[[:space:]]*(@|#)includedir[[:space:]]+/etc/sudoers\.d([[:space:]]|$)' /etc/sudoers; then
    BACKUP="/etc/sudoers.backup.$(date +%Y%m%d-%H%M%S)"
    echo "[INFO] /etc/sudoers.d is not included. Creating backup: $BACKUP"
    cp -a /etc/sudoers "$BACKUP"
    printf '\n@includedir /etc/sudoers.d\n' >> /etc/sudoers

    if ! "$VISUDO" -cf /etc/sudoers >/dev/null; then
        echo "[ERROR] sudoers validation failed; restoring backup."
        cp -a "$BACKUP" /etc/sudoers
        exit 1
    fi
fi

SAFE_USER="${TARGET_USER//./_}"
SUDOERS_FILE="/etc/sudoers.d/99-user-${SAFE_USER}"
TMP_SUDOERS="$(mktemp)"
trap 'rm -f "$TMP_SUDOERS"' EXIT

# Standard password-protected sudo access. This does NOT enable NOPASSWD.
printf '%s ALL=(ALL) ALL\n' "$TARGET_USER" > "$TMP_SUDOERS"
chmod 0440 "$TMP_SUDOERS"

if ! "$VISUDO" -cf "$TMP_SUDOERS" >/dev/null; then
    echo "[ERROR] Generated sudoers entry is invalid."
    exit 1
fi

install -o root -g root -m 0440 "$TMP_SUDOERS" "$SUDOERS_FILE"

if ! "$VISUDO" -cf /etc/sudoers >/dev/null; then
    rm -f "$SUDOERS_FILE"
    echo "[ERROR] Final sudoers validation failed. The new entry was removed."
    exit 1
fi

echo
echo "[ OK ] sudo is installed and configured."
echo "[ OK ] User '$TARGET_USER' now has full sudo access."
echo "[INFO] sudoers entry: $SUDOERS_FILE"
ROOT_SCRIPT

chmod 0700 "$ROOT_HELPER"

echo
info "Current account: $TARGET_USER"

if [[ "$(id -u)" -eq 0 ]]; then
    # This path is normally reached only when invoked through sudo, because
    # direct root execution is rejected above.
    /bin/bash "$ROOT_HELPER" "$TARGET_USER"
else
    ELEVATED=false

    if command -v sudo >/dev/null 2>&1; then
        info "sudo is installed. Checking whether this account can already use it..."

        if sudo -n true 2>/dev/null; then
            sudo /bin/bash "$ROOT_HELPER" "$TARGET_USER"
            ELEVATED=true
        else
            info "sudo may require your user password."
            if sudo -v; then
                sudo /bin/bash "$ROOT_HELPER" "$TARGET_USER"
                ELEVATED=true
            else
                warn "sudo authentication failed or this account is not allowed to use sudo."
            fi
        fi
    fi

    if [[ "$ELEVATED" != true ]]; then
        if ! command -v su >/dev/null 2>&1; then
            error "'su' is not available and sudo could not be used."
            exit 1
        fi

        echo
        info "Falling back to su."
        info "Enter the root password when prompted."
        echo

        # su/PAM reads the password directly from the terminal.
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
