#!/bin/bash
set -euo pipefail

# تصميم مُحسّن و ألوان مميزة - تحديث نسخة phpMyAdmin مع واجهة نصية أفضل (عربي/إنجليزي)
# Usage: ./phpmyadmin_v_changer.sh

# Colors (ANSI)
RESET="\033[0m"
BOLD="\033[1m"
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
MAGENTA="\033[35m"
CYAN="\033[36m"

# Helper to print styled lines
print_header() {
    echo -e "${BOLD}${CYAN}============================================${RESET}"
    echo -e "${BOLD}${MAGENTA}    أداة تغيير نسخة phpMyAdmin — phpMyAdmin Changer${RESET}"
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
    print_err "يجب تشغيل السكربت بصلاحيات الروت (sudo)."
    exit 1
fi

print_header

# Ask user for version (Arabic prompt with example)
read -rp "$(echo -e ${BOLD})ما هي نسخة phpMyAdmin التي تريد استخدامها؟ (مثال: 5.2.2): ${RESET}" phpmyadmin_version
phpmyadmin_version="${phpmyadmin_version// /}" # trim spaces

if [[ -z "$phpmyadmin_version" ]]; then
    print_err "لم تُدخل نسخة. إنهاء."
    exit 1
fi

# Constants
DEST_DIR="/usr/local/CyberCP/public/phpmyadmin"
TIMESTAMP="$(date +%Y%m%d%H%M%S)"
BACKUP_DIR="${DEST_DIR}_backup_${TIMESTAMP}"
TMP_DIR="$(mktemp -d -t phpmyadminXXXX)"
DOWNLOAD_URL="https://files.phpmyadmin.net/phpMyAdmin/${phpmyadmin_version}/phpMyAdmin-${phpmyadmin_version}-all-languages.tar.gz"
TAR_FILE="$TMP_DIR/phpmyadmin.tar.gz"

# Cleanup on exit
cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

print_step "التحقق من وجود أدوات التحميل..."
if command -v wget >/dev/null 2>&1; then
    DOWNLOADER="wget"
elif command -v curl >/dev/null 2>&1; then
    DOWNLOADER="curl"
else
    print_err "لا يوجد wget أو curl مُثبت. رجاءً ثبّت أحدهما."
    exit 1
fi
print_ok "مُحدد أداة التحميل: ${DOWNLOADER}"

print_step "تحميل phpMyAdmin $phpmyadmin_version ..."
if [[ "$DOWNLOADER" == "wget" ]]; then
    if ! wget -q -O "$TAR_FILE" "$DOWNLOAD_URL"; then
        print_err "فشل تحميل النسخة $phpmyadmin_version من $DOWNLOAD_URL"
        print_warn "تحقق من وجود النسخة على: https://www.phpmyadmin.net/downloads/"
        exit 1
    fi
else
    if ! curl -fsSL -o "$TAR_FILE" "$DOWNLOAD_URL"; then
        print_err "فشل تحميل النسخة $phpmyadmin_version من $DOWNLOAD_URL"
        print_warn "تحقق من وجود النسخة على: https://www.phpmyadmin.net/downloads/"
        exit 1
    fi
fi
print_ok "تم تحميل الأرشيف إلى $TAR_FILE"

# Backup existing installation if present
if [[ -d "$DEST_DIR" ]]; then
    print_step "عمل نسخة احتياطية من التثبيت الحالي إلى: $BACKUP_DIR"
    rm -rf "$BACKUP_DIR" || true
    mv "$DEST_DIR" "$BACKUP_DIR"
    print_ok "تم النقل إلى $BACKUP_DIR"
else
    print_step "إنشاء مجلد الوجهة: $DEST_DIR"
    mkdir -p "$DEST_DIR"
    print_ok "مجلد الوجهة جاهز"
fi

# Preserve important configs: config.inc.php and phpmyadminsignin.php
for cfg in config.inc.php phpmyadminsignin.php; do
    if [[ -f "${BACKUP_DIR}/${cfg}" ]]; then
        print_step "نقل $cfg من النسخة الاحتياطية إلى مجلد مؤقت"
        mv -f "${BACKUP_DIR}/${cfg}" "$TMP_DIR/" || true
    fi
done

# Extract new version
print_step "فك ضغط الأرشيف إلى $DEST_DIR"
mkdir -p "$DEST_DIR"
if ! tar -xzf "$TAR_FILE" -C "$DEST_DIR" --strip-components=1; then
    print_err "فشل فك ضغط الأرشيف. إنهاء."
    exit 1
fi
print_ok "انتهى فك الضغط"

# Restore configs if existed
for cfg in config.inc.php phpmyadminsignin.php; do
    if [[ -f "$TMP_DIR/$cfg" ]]; then
        print_step "استعادة $cfg إلى $DEST_DIR"
        mv -f "$TMP_DIR/$cfg" "$DEST_DIR/$cfg"
        print_ok "تم استعادة $cfg"
    fi
done

# Ensure tmp/twig exists and set permissions
print_step "ضبط الأذونات (ملفات 644 ومجلدات 755)"
cd "$DEST_DIR"
find . -type d -exec chmod 755 {} \; >/dev/null 2>&1 || true
find . -type f -exec chmod 644 {} \; >/dev/null 2>&1 || true

# Create tmp/twig and set owner to lscpd if exists, otherwise to www-data or current user
mkdir -p "$DEST_DIR/tmp/twig"
if id -u lscpd >/dev/null 2>&1; then
    CHOWN_TARGET="lscpd:lscpd"
elif id -u www-data >/dev/null 2>&1; then
    CHOWN_TARGET="www-data:www-data"
else
    CHOWN_TARGET="$(id -u -n):$(id -g -n)"
fi

chown -R "$CHOWN_TARGET" "$DEST_DIR/tmp" || true
print_ok "الأذونات مُحدثة. المالك: $CHOWN_TARGET"

echo ""
echo -e "${BOLD}${GREEN}تم تغيير phpMyAdmin إلى النسخة ${phpmyadmin_version}!${RESET}"
echo -e "${CYAN}المسار: ${DEST_DIR}${RESET}"

if [[ -d "$BACKUP_DIR" ]]; then
    echo -e "${YELLOW}ملحوظة: تم حفظ النسخة السابقة في: ${BACKUP_DIR}${RESET}"
fi

echo -e "${MAGENTA}نصائح بعد التحديث:${RESET}"
echo -e " - أعد تشغيل خدمة الويب إذا لزم الأمر (مثال: systemctl restart lsws أو systemctl restart apache2/nginx)."
echo -e " - قم بمراجعة ملف config.inc.php للتأكد من الإعدادات والحصول على الدخول التلقائي إن وُجد."
echo -e " - للاطلاع على السجلات: tail -n 50 /var/log/*webserver*"

exit 0