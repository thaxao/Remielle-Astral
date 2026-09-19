#!/usr/bin/env bash
# One-line uninstaller for Remielle Astral on Linux.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/thaxao/Remielle-Astral/main/tools/uninstall.sh | bash
#
set -euo pipefail

# 1. Safety Guard: Validate HOME environment variable
if [ -z "${HOME:-}" ] || [ "$HOME" = "/" ]; then
  echo "error: HOME directory is not properly set. Aborting for safety." >&2
  exit 1
fi

INSTALL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/remielle-astral"
BIN_LINK="${HOME}/.local/bin/remielle-astral"
APP_DESKTOP="${XDG_DATA_HOME:-$HOME/.local/share}/applications/io.github.thaxao.RemielleAstral.desktop"
APP_ICON="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/256x256/apps/io.github.thaxao.RemielleAstral.png"

# 2. Safety Guard: Ensure target directory strictly ends with /remielle-astral
case "$INSTALL_DIR" in
  */remielle-astral) ;;
  *)
    echo "error: Safety guard triggered: Refusing to delete path that does not match */remielle-astral ($INSTALL_DIR)" >&2
    exit 1
    ;;
esac

RESET="\033[0m"
BOLD="\033[1m"
GREEN="\033[32m"
CYAN="\033[36m"
YELLOW="\033[33m"
RED="\033[31m"

say() { printf "${CYAN}==>${RESET} ${BOLD}%s${RESET}\n" "$*"; }
ok()  { printf "${GREEN}  ✓${RESET} %s\n" "$*"; }
die() { printf "${RED}error:${RESET} %s\n" "$*" >&2; exit 1; }

# Concurrency Guard: prevent concurrent installer or uninstaller runs
LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/remielle-astral-op.lock"
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
  die "มีกระบวนการติดตั้งหรือถอนการติดตั้ง Remielle Astral กำลังทำงานอยู่แล้ว (Another install/uninstall process is currently running)"
fi

# Duplicate Uninstall Guard: check if Remielle Astral is installed at all
if [ ! -d "$INSTALL_DIR" ] && [ ! -L "$BIN_LINK" ] && [ ! -f "$BIN_LINK" ] && [ ! -f "$APP_DESKTOP" ] && [ ! -f "$APP_ICON" ]; then
  say "ไม่พบการติดตั้ง Remielle Astral ในระบบ (Remielle Astral is not installed on this system)"
  exit 0
fi

say "Uninstalling Remielle Astral..."

# Stop any running launcher instances
if pgrep -f "remielle-astral" >/dev/null 2>&1; then
  say "Stopping running Remielle Astral process..."
  pkill -f "remielle-astral" || true
  sleep 1
fi

# Ask user if they want to wipe configuration / settings
REMOVE_CONFIG="n"
if [ -e /dev/tty ]; then
  printf "\n${YELLOW}${BOLD}ต้องการลบการตั้งค่า (Settings/Config, โฟลเดอร์เซิร์ฟเวอร์/ไคลเอนต์, แคช) ด้วยหรือไม่?${RESET}\n"
  printf "• หากลบ: ครั้งหน้าเมื่อติดตั้งใหม่ จะต้องผ่านขั้นตอนตั้งค่าเริ่มต้นใหม่ทั้งหมด\n"
  printf "• หากไม่ลบ: จะเก็บการตั้งค่าไว้ ทำให้ติดตั้งใหม่แล้วใช้งานต่อได้ทันที\n"
  read -r -p "ลบการตั้งค่าและแคชด้วยหรือไม่? [y/N]: " REMOVE_CONFIG </dev/tty || REMOVE_CONFIG="n"
fi

# Remove application directory or preserve settings
if [ -d "$INSTALL_DIR" ]; then
  if [[ "$REMOVE_CONFIG" =~ ^[Yy]$ ]]; then
    rm -rf "$INSTALL_DIR"
    rm -rf "$HOME/.remielle-cache"
    ok "Removed installation directory and all settings/cache"
  else
    # Preserve settings.json and mods/ if they exist
    find "$INSTALL_DIR" -mindepth 1 -maxdepth 1 ! -name "settings.json" ! -name "mods" -exec rm -rf {} +
    ok "Removed application binaries and assets (preserved settings.json for future reinstall)"
  fi
fi

# Remove binary symlink
if [ -L "$BIN_LINK" ] || [ -f "$BIN_LINK" ]; then
  rm -f "$BIN_LINK"
  ok "Removed: $BIN_LINK"
fi

# Remove desktop application entry
if [ -f "$APP_DESKTOP" ]; then
  rm -f "$APP_DESKTOP"
  ok "Removed: $APP_DESKTOP"
fi

# Remove desktop application icon
if [ -f "$APP_ICON" ]; then
  rm -f "$APP_ICON"
  ok "Removed: $APP_ICON"
fi

# Remove WebKit data directory
rm -rf "${XDG_DATA_HOME:-$HOME/.local/share}/io.github.thaxao.RemielleAstral" 2>/dev/null || true

# Refresh desktop application database for KDE and GNOME
if command -v kbuildsycoca6 >/dev/null 2>&1; then
  kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
elif command -v kbuildsycoca5 >/dev/null 2>&1; then
  kbuildsycoca5 --noincremental >/dev/null 2>&1 || true
fi
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "${XDG_DATA_HOME:-$HOME/.local/share}/applications" >/dev/null 2>&1 || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -f -t "${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor" >/dev/null 2>&1 || true
fi

printf "\n${GREEN}${BOLD}Remielle Astral has been uninstalled successfully.${RESET}\n\n"
