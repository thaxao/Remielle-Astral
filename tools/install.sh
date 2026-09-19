#!/usr/bin/env bash
# One-line installer for Remielle Astral on Linux.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/thaxao/Remielle-Astral/main/tools/install.sh | bash
#
set -euo pipefail

REPO="${REMIELLE_REPO:-thaxao/Remielle-Astral}"
INSTALL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/remielle-astral"
BIN_DIR="${HOME}/.local/bin"
APP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
ICON_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/256x256/apps"

RESET="\033[0m"
BOLD="\033[1m"
GREEN="\033[32m"
BLUE="\033[34m"
CYAN="\033[36m"
RED="\033[31m"

say() { printf "${CYAN}==>${RESET} ${BOLD}%s${RESET}\n" "$*"; }
ok()  { printf "${GREEN}  ✓${RESET} %s\n" "$*"; }
die() { printf "${RED}error:${RESET} %s\n" "$*" >&2; exit 1; }

printf "${BOLD}${BLUE}"
cat << 'EOF'
  ____                _      _ _             _        _             _ 
 |  _ \ ___ _ __ ___ (_) ___| | | ___       / \   ___| |_ _ __ __ _| |
 | |_) / _ \ '_ ` _ \| |/ _ \ | |/ _ \     / _ \ / __| __| '__/ _` | |
 |  _ <  __/ | | | | | |  __/ | |  __/    / ___ \\__ \ |_| | | (_| | |
 |_| \_\___|_| |_| |_|_|\___|_|_|\___|   /_/   \_\___/\__|_|  \__,_|_|
EOF
printf "${RESET}\n"
say "Installing Remielle Astral for Linux..."

# Check requirements
command -v curl >/dev/null 2>&1 || die "curl is required to install Remielle Astral"
command -v unzip >/dev/null 2>&1 || die "unzip is required to install Remielle Astral"

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64) PLATFORM="linux-x86_64" ;;
  *) die "Remielle Astral only supports x86_64 Linux currently (detected: $ARCH)" ;;
esac

say "Fetching release information from GitHub ($REPO)..."
LATEST_JSON="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null || true)"
if [ -z "$LATEST_JSON" ] || echo "$LATEST_JSON" | grep -q "Not Found"; then
  # Fallback: query all releases and take newest
  LATEST_JSON="$(curl -fsSL "https://api.github.com/repos/$REPO/releases" 2>/dev/null | grep -E '("tag_name"|"browser_download_url")' | head -n 30 || true)"
fi

ASSET_URL="$(echo "$LATEST_JSON" | grep -o "https://[^\"']*remielle-astral-[^\"']*-$PLATFORM\.zip" | head -n 1 || true)"
TAG="$(echo "$LATEST_JSON" | grep -o '"tag_name": *"[^"]*"' | head -n 1 | cut -d'"' -f4 || true)"

if [ -z "$ASSET_URL" ]; then
  # Fallback to direct latest release tag URL
  TAG="${TAG:-latest}"
  ASSET_URL="https://github.com/$REPO/releases/download/$TAG/remielle-astral-$PLATFORM.zip"
fi

say "Downloading Remielle Astral ${TAG}..."
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
ZIP_PATH="$TMP_DIR/remielle-astral.zip"

if ! curl -fSL --progress-bar -o "$ZIP_PATH" "$ASSET_URL"; then
  die "Failed to download $ASSET_URL"
fi
ok "Downloaded package"

say "Installing to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
unzip -q -o "$ZIP_PATH" -d "$TMP_DIR/extracted"

EXTRACTED_ROOT="$(find "$TMP_DIR/extracted" -maxdepth 2 -type f -name "remielle-astral" -exec dirname {} \; | head -n 1)"
if [ -z "$EXTRACTED_ROOT" ]; then
  die "Archive did not contain remielle-astral executable"
fi

cp -r "$EXTRACTED_ROOT"/* "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/remielle-astral"
ok "Extracted files into $INSTALL_DIR"

# Link binary to ~/.local/bin
mkdir -p "$BIN_DIR"
ln -sf "$INSTALL_DIR/remielle-astral" "$BIN_DIR/remielle-astral"
ok "Created symlink: $BIN_DIR/remielle-astral"

# Desktop integration
mkdir -p "$APP_DIR" "$ICON_DIR"
if [ -f "$INSTALL_DIR/src/static/icon.png" ]; then
  cp "$INSTALL_DIR/src/static/icon.png" "$ICON_DIR/io.github.thaxao.RemielleAstral.png"
elif [ -f "$INSTALL_DIR/icon.png" ]; then
  cp "$INSTALL_DIR/icon.png" "$ICON_DIR/io.github.thaxao.RemielleAstral.png"
fi

PRIME=""
if command -v prime-run >/dev/null 2>&1; then
  PRIME="prime-run "
fi

cat << DESKTOP > "$APP_DIR/io.github.thaxao.RemielleAstral.desktop"
[Desktop Entry]
Type=Application
Name=Remielle Astral
Comment=Remielle (Zenless Zone Zero) server launcher
Exec=${PRIME}${BIN_DIR}/remielle-astral
Path=${INSTALL_DIR}
Icon=io.github.thaxao.RemielleAstral
Terminal=false
Categories=Game;
StartupWMClass=io.github.thaxao.RemielleAstral
StartupNotify=true
DESKTOP
chmod 644 "$APP_DIR/io.github.thaxao.RemielleAstral.desktop"

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$APP_DIR" >/dev/null 2>&1 || true
fi
ok "Registered desktop application menu shortcut"

printf "\n${GREEN}${BOLD}Installation completed successfully!${RESET}\n"
printf "You can launch Remielle Astral by running:\n"
printf "  ${BOLD}remielle-astral${RESET}  (or find it in your application menu)\n\n"
