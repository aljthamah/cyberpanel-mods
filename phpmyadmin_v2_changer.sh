#!/bin/bash
set -euo pipefail

# Enhanced phpMyAdmin version changer script (English only)
# Usage: ./phpmyadmin_v2_changer.sh

# Colors (ANSI)
RESET="\033[0m"
BOLD="\033[1m"
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
MAGENTA="\033[35m"
CYAN="\033[36m"

# Helpers
print_header() {
    echo -e "${BOLD}${CYAN}============================================${RESET}"
    echo -e "${BOLD}${MAGENTA}     phpMyAdmin Version Changer Tool${RESET}"
    echo -e "${BOLD}${CYAN}============================================${RESET}"
}

print_step() {
    echo -e "${BOLD}${BLUE}➜ $1${RESET}"
}

print_ok() {
    echo -e "${GREEN}✔ $1${RESET}"
}

print_warn() {
    echo -e "${YELLOW}⚠ $1${RESET}"
}

print_err() {
    echo -e "${RED}✖ $1${RESET}"
}

# Ensure running as root
if [[ $EUID -ne 0 ]]; then
    print_err "This script must be run as root (sudo)."
    exit 1
fi

print_header

# Confirmation before starting
read -rp "Do you want to continue? (Y/N): " confirm
case "$confirm" in
    [Yy]* ) print_ok "Continuing...";;
    [Nn]* ) print_warn "Cancelled by user."; exit 0;;
    * ) print_err "Invalid choice. Exiting."; exit 1;;
esac

# Ask user for version (fixed: no raw \033 text shown)
read -rp $'\033[1mEnter the phpMyAdmin version you want (e.g. 5.2.2):\033[0m ' phpmyadmin_version
phpmyadmin_version="${phpmyadmin_version// /}" # trim spaces

if [[ -z "$phpmyadmin_version" ]]; then
    print_err "No version entered. Exiting."
    exit 1
fi

# Constants
DEST_DIR="/usr/local/CyberCP/public/phpmyadmin"
TIMESTAMP="$(date +%Y%m%d%H%M%S)"
BACKUP_DIR="${DEST_DIR}_backup_${TIMESTAMP}"
TMP_DIR="$(mktemp -d -t phpmyadminXXXX)"
DOWNLOAD_URL="https://files.phpmyadmin.net/phpMyAdmin/${phpmyadmin_version}/phpMyAdmin-${phpmyadmin_version}-all-languages.tar.gz"
TAR_FILE="$TMP_DIR/phpmyadmin.tar.gz"

# Cleanup
cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

print_step "Checking for download tools..."
if command -v wget >/dev/null 2>&1; then
    DOWNLOADER="wget"
elif command -v curl >/dev/null 2>&1; then
    DOWNLOADER="curl"
else
    print_err "Neither wget nor curl is installed. Please install one of them."
    exit 1
fi
print_ok "Download tool detected: ${DOWNLOADER}"

print_step "Downloading phpMyAdmin $phpmyadmin_version ..."
if [[ "$DOWNLOADER" == "wget" ]]; then
    if ! wget -q -O "$TAR_FILE" "$DOWNLOAD_URL"; then
        print_err "Failed to download version $phpmyadmin_version from $DOWNLOAD_URL"
        print_warn "Check available versions at: https://www.phpmyadmin.net/downloads/"
        exit 1
    fi
else
    if ! curl -fsSL -o "$TAR_FILE" "$DOWNLOAD_URL"; then
        print_err "Failed to download version $phpmyadmin_version from $DOWNLOAD_URL"
        print_warn "Check available versions at: https://www.phpmyadmin.net/downloads/"
        exit 1
    fi
fi
print_ok "Downloaded archive to $TAR_FILE"

# Backup existing installation
if [[ -d "$DEST_DIR" ]]; then
    print_step "Backing up current installation to: $BACKUP_DIR"
    rm -rf "$BACKUP_DIR" || true
    mv "$DEST_DIR" "$BACKUP_DIR"
    print_ok "Backup created at $BACKUP_DIR"
else
    print_step "Creating destination folder: $DEST_DIR"
    mkdir -p "$DEST_DIR"
    print_ok "Destination folder ready"
fi

# Preserve configs
for cfg in config.inc.php phpmyadminsignin.php; do
    if [[ -f "${BACKUP_DIR}/${cfg}" ]]; then
        print_step "Saving $cfg from backup to temp"
        mv -f "${BACKUP_DIR}/${cfg}" "$TMP_DIR/" || true
    fi
done

# Extract new version
print_step "Extracting archive to $DEST_DIR"
mkdir -p "$DEST_DIR"
if ! tar -xzf "$TAR_FILE" -C "$DEST_DIR" --strip-components=1; then
    print_err "Extraction failed. Exiting."
    exit 1
fi
print_ok "Extraction completed"

# Restore configs
for cfg in config.inc.php phpmyadminsignin.php; do
    if [[ -f "$TMP_DIR/$cfg" ]]; then
        print_step "Restoring $cfg to $DEST_DIR"
        mv -f "$TMP_DIR/$cfg" "$DEST_DIR/$cfg"
        print_ok "$cfg restored"
    fi
done

# Fix permissions
print_step "Setting file and folder permissions"
cd "$DEST_DIR"
find . -type d -exec chmod 755 {} \; >/dev/null 2>&1 || true
find . -type f -exec chmod 644 {} \; >/dev/null 2>&1 || true

mkdir -p "$DEST_DIR/tmp/twig"
if id -u lscpd >/dev/null 2>&1; then
    CHOWN_TARGET="lscpd:lscpd"
elif id -u www-data >/dev/null 2>&1; then
    CHOWN_TARGET="www-data:www-data"
else
    CHOWN_TARGET="$(id -u -n):$(id -g -n)"
fi
chown -R "$CHOWN_TARGET" "$DEST_DIR/tmp" || true
print_ok "Permissions updated. Owner: $CHOWN_TARGET"

echo ""
echo -e "${BOLD}${GREEN}phpMyAdmin has been updated to version ${phpmyadmin_version}!${RESET}"
echo -e "${CYAN}Path: ${DEST_DIR}${RESET}"

if [[ -d "$BACKUP_DIR" ]]; then
    echo -e "${YELLOW}Note: Previous version was saved at: ${BACKUP_DIR}${RESET}"
fi

echo -e "${MAGENTA}Post-update tips:${RESET}"
echo -e " - Restart your web server if required (e.g. systemctl restart lsws/apache2/nginx)."
echo -e " - Review config.inc.php to confirm settings."
echo -e " - Check logs if you encounter issues: tail -n 50 /var/log/*webserver*"

echo ""
echo -e "${BOLD}${BLUE}Script updated by MUHAMMED Alj <admin@aljup.com>${RESET}"

exit 0
