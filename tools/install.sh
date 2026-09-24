#!/usr/bin/env bash
# Remielle Astral installer for Linux.
#
#   curl -fsSL https://raw.githubusercontent.com/thaxao/Remielle-Astral/main/tools/install.sh | bash
#   curl -fsSL .../install.sh | bash -s -- --version v1.3.1.b3.3.3
#   bash install.sh --zip ~/Downloads/remielle-astral-1.3.1.b3.3.3-linux-x86_64.zip
#
# Options
#   --version TAG   install that release instead of the newest ("v" optional)
#   --zip FILE      install a zip already downloaded; a SHA256SUMS beside it is
#                   checked when there is one
#   --dir DIR       install folder (default ~/.local/share/remielle-astral)
#   --check         only show what is installed and what the newest release is
#   --rollback      put back the version the last install replaced
#   --force         reinstall even when that version is already installed
#   --no-menu       no application-menu entry, icon or ~/.local/bin link
#   --no-launch     do not offer to start it afterwards
#   -y, --yes       answer every question with its default
#
# Only the program's own files (the release's MANIFEST) are replaced.
# settings.json, the saves, the Custom server, the mod library and the caches
# in the same folder are never touched.  The version being replaced is kept
# for --rollback.  Pre-releases count: alpha builds are published that way.
#
# Environment: REMIELLE_REPO=owner/name (default thaxao/Remielle-Astral),
# REMIELLE_RELEASES_URL=<a releases list in the GitHub shape> for a mirror.

# Nothing runs until `main "$@"` on the last line, so a download cut short by
# the network never runs half a script.

set -uo pipefail
export LC_ALL=C

REPO="${REMIELLE_REPO:-thaxao/Remielle-Astral}"
DATA_HOME="${XDG_DATA_HOME:-${HOME:-}/.local/share}"
DIR="$DATA_HOME/remielle-astral"
BIN_DIR="${HOME:-}/.local/bin"
APP_DIR="$DATA_HOME/applications"
ICON_DIR="$DATA_HOME/icons/hicolor/256x256/apps"
APP_ID="io.github.thaxao.RemielleAstral"
PLATFORM="linux-x86_64"
LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/remielle-astral-op.lock"

# Files of releases made before the zips carried a MANIFEST.
LEGACY_FILES="remielle-astral remielle-astral.old README.md LICENSE icon.png MANIFEST
tools/remielle-update tools/build-official-patch tools/import-patch
tools/install.sh tools/install.ps1 tools/install.cmd
tools/update.sh tools/update.ps1 tools/update.cmd
tools/uninstall.sh tools/uninstall.ps1 tools/uninstall.cmd
patch/Pryce.exe patch/Armorer.dll"

want_tag="" zip_file="" mode="install" force=0 menu=1 launch=1 yes=0 thai=0
TMP="" TAG="" URL="" SUMS_URL="" ZIP_NAME="" NEW_VERSION="" SHA=""

# ------------------------------------------------------------------ output --
if [ -t 1 ]; then
  B=$'\033[1m' G=$'\033[32m' C=$'\033[36m' Y=$'\033[33m' R=$'\033[31m' D=$'\033[2m' N=$'\033[0m'
else
  B="" G="" C="" Y="" R="" D="" N=""
fi
# T "english" "thai": the message in the user's language.
T() { if [ "$thai" = 1 ] && [ -n "${2:-}" ]; then printf '%s' "$2"; else printf '%s' "$1"; fi; }
say()  { printf '%s==>%s %s%s%s\n' "$C" "$N" "$B" "$*" "$N"; }
ok()   { printf '  %s✓%s %s\n' "$G" "$N" "$*"; }
note() { printf '  %s·%s %s\n' "$D" "$N" "$*"; }
warn() { printf '  %s!%s %s\n' "$Y" "$N" "$*" >&2; }
die()  { printf '%serror:%s %s\n' "$R" "$N" "$*" >&2; exit 1; }

# ask "question" y|n: 0 for yes.  Without a terminal (curl | bash inside a
# script) or with --yes: the default answer.
ask() {
  local answer="" hint="[y/N]"
  [ "$2" = y ] && hint="[Y/n]"
  if [ "$yes" = 1 ] || ! { : </dev/tty; } 2>/dev/null; then
    [ "$2" = y ]
    return
  fi
  printf '%s %s ' "$1" "$hint" >/dev/tty
  read -r answer </dev/tty || answer=""
  case "$answer" in
    [Yy]*) return 0 ;;
    [Nn]*) return 1 ;;
    *) [ "$2" = y ] ;;
  esac
}

usage() {
  cat <<'EOF'
Remielle Astral installer for Linux

  install.sh                    install or update to the newest release
  install.sh --version TAG      install that release
  install.sh --zip FILE         install a downloaded zip (checked against a SHA256SUMS beside it)
  install.sh --check            show the installed and the newest version
  install.sh --rollback         put back the version the last install replaced

  --dir DIR     install folder (default ~/.local/share/remielle-astral)
  --force       reinstall the same version
  --no-menu     no menu entry, icon or ~/.local/bin link
  --no-launch   do not offer to start it
  -y, --yes     answer every question with its default
EOF
}

# ---------------------------------------------------------------- versions --
# Is $1 newer than $2?  The launcher's own rules: the LAUNCHER.bGAME numbers
# first (the "b" is skipped), then a release beats a pre-release, then
# pre-release names in order.  Anything after a space is a label.
ver_gt() {
  local a="${1#[vV]}" b="${2#[vV]}"
  a="${a%% *}"; b="${b%% *}"
  local an="${a%%-*}" bn="${b%%-*}" ap="" bp=""
  [ "$an" != "$a" ] && ap="${a#*-}"
  [ "$bn" != "$b" ] && bp="${b#*-}"
  local al="$an" bl="$bn" ag="" bg="" segment left right i x y
  if [[ "$an" == *'.b'* ]]; then al="${an%%.b*}"; ag="${an#*.b}"; fi
  if [[ "$bn" == *'.b'* ]]; then bl="${bn%%.b*}"; bg="${bn#*.b}"; fi
  local -a va vb
  for segment in "$al|$bl" "$ag|$bg"; do
    left="${segment%%|*}"; right="${segment#*|}"
    [ -n "$left" ] && [ -n "$right" ] || continue
    IFS=. read -r -a va <<<"$left"
    IFS=. read -r -a vb <<<"$right"
    for i in 0 1 2 3 4 5 6 7; do
      x="${va[i]:-0}"; y="${vb[i]:-0}"
      x="${x#"${x%%[0-9]*}"}"; y="${y#"${y%%[0-9]*}"}"
      case "$x" in ''|*[!0-9]*) x=0 ;; esac
      case "$y" in ''|*[!0-9]*) y=0 ;; esac
      if [ "$((10#$x))" -ne "$((10#$y))" ]; then
        [ "$((10#$x))" -gt "$((10#$y))" ]
        return
      fi
    done
  done
  [ -z "$ap" ] && [ -n "$bp" ] && return 0
  [ -n "$ap" ] && [ -z "$bp" ] && return 1
  [[ "$ap" > "$bp" ]]
}

# The version of the launcher in folder $1, or "".  A build that knows
# --version says so in its usage text; an older one would open its window
# instead, so it is only asked when it can answer.
version_in() {
  local exe="$1/remielle-astral" v=""
  if [ -x "$exe" ] && grep -qaF 'usage: remielle-astral [--version' "$exe" 2>/dev/null; then
    v="$(timeout 5 "$exe" --version 2>/dev/null | head -1)" || v=""
  fi
  if [ -z "$v" ] && [ -f "$1/.install-info" ]; then
    v="$(sed -n 's/^version=//p' "$1/.install-info" | head -1)"
  fi
  printf '%s' "$v"
}

# ------------------------------------------------------------------- files --
# Relative paths only, nothing climbing out of the folder.
safe_paths() { grep -v -e '^/' -e '^$' -e '\(^\|/\)\.\.\(/\|$\)' || true; }

# The program's own files in folder $1: its MANIFEST, else the known list.
program_files() {
  if [ -f "$1/MANIFEST" ]; then
    tr -d '\r' <"$1/MANIFEST" | safe_paths
  else
    # shellcheck disable=SC2086
    printf '%s\n' $LEGACY_FILES
  fi
}

list_tree() { (cd "$1" && find . -type f | sed 's|^\./||' | LC_ALL=C sort); }

is_elf() { [ "$(head -c 4 "$1" 2>/dev/null | od -An -c | tr -d ' \n')" = '177ELF' ]; }

# Processes running the file $1, found by their exe link: names and
# arguments do not matter, and nothing else that mentions "remielle-astral"
# (an editor, this script, the servers) is touched.
pids_of() {
  local p exe
  for p in /proc/[0-9]*; do
    exe="$(readlink "$p/exe" 2>/dev/null)" || continue
    case "$exe" in "$1"|"$1 (deleted)") printf '%s\n' "${p#/proc/}" ;; esac
  done
}

stop_launcher() {
  local exe pids
  [ -e "$DIR/remielle-astral" ] || return 0
  exe="$(cd "$DIR" && pwd -P)/remielle-astral"
  pids="$(pids_of "$exe" | tr '\n' ' ')"
  [ -n "${pids// /}" ] || return 0
  if ! ask "$(T "Remielle Astral is open (pid ${pids% }). Close it to continue?" "Remielle Astral เปิดอยู่ (pid ${pids% }) ปิดเพื่อทำต่อไหม?")" y; then
    die "$(T "Close Remielle Astral and run this again." "ปิด Remielle Astral แล้วรันใหม่อีกครั้ง")"
  fi
  # shellcheck disable=SC2086
  kill $pids 2>/dev/null
  for _ in $(seq 1 50); do
    [ -n "$(pids_of "$exe")" ] || break
    sleep 0.1
  done
  pids="$(pids_of "$exe" | tr '\n' ' ')"
  # shellcheck disable=SC2086
  [ -n "${pids// /}" ] && kill -9 $pids 2>/dev/null
  ok "$(T "Closed Remielle Astral (running servers keep going)" "ปิด Remielle Astral แล้ว (เซิร์ฟที่รันอยู่ยังทำงานต่อ)")"
}

# Copies the program in folder $1 over $DIR.  What it replaces goes to
# .remielle-cache/previous for --rollback, and files the old version had and
# the new one does not are removed.  Everything else in $DIR stays.
install_from() {
  local from="$1" prev="$DIR/.remielle-cache/previous" f new_list old_list
  mkdir -p "$DIR" || die "cannot create $DIR"
  [ -f "$from/MANIFEST" ] || { list_tree "$from"; echo MANIFEST; } | LC_ALL=C sort >"$from/MANIFEST.new"
  [ -f "$from/MANIFEST.new" ] && mv "$from/MANIFEST.new" "$from/MANIFEST"
  new_list="$(program_files "$from")"

  if [ -e "$DIR/remielle-astral" ]; then
    old_list="$(program_files "$DIR")"
    rm -rf "$prev.new" && mkdir -p "$prev.new"
    while IFS= read -r f; do
      [ -f "$DIR/$f" ] || continue
      mkdir -p "$prev.new/$(dirname "$f")" && cp -p "$DIR/$f" "$prev.new/$f"
    done <<<"$old_list"
    { list_tree "$prev.new" | grep -vx MANIFEST; echo MANIFEST; } | LC_ALL=C sort >"$prev.new/MANIFEST.new"
    mv "$prev.new/MANIFEST.new" "$prev.new/MANIFEST"
    rm -rf "$prev" && mv "$prev.new" "$prev"
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      grep -qxF -- "$f" <<<"$new_list" || rm -f "$DIR/$f"
    done <<<"$old_list"
  fi

  while IFS= read -r f; do
    [ -f "$from/$f" ] || continue
    mkdir -p "$DIR/$(dirname "$f")" || die "cannot create $DIR/$(dirname "$f")"
    # Written beside and renamed over, so a file in use is replaced whole.
    { cp -p "$from/$f" "$DIR/$f.astral-new" && mv -f "$DIR/$f.astral-new" "$DIR/$f"; } || die "cannot write $DIR/$f"
  done <<<"$new_list"
  chmod +x "$DIR/remielle-astral" 2>/dev/null
  for f in "$DIR"/tools/*.sh "$DIR/tools/remielle-update" "$DIR/tools/build-official-patch"; do
    [ -f "$f" ] && chmod +x "$f"
  done
  rmdir "$DIR/tools" "$DIR/patch" 2>/dev/null
  return 0
}

write_info() { # version tag source sha256
  {
    echo "version=$1"
    echo "tag=$2"
    echo "source=$3"
    echo "sha256=$4"
    echo "installed_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } >"$DIR/.install-info"
}

# --------------------------------------------------------------- releases --
releases_json() {
  local url="${REMIELLE_RELEASES_URL:-https://api.github.com/repos/$REPO/releases?per_page=30}"
  curl -fsSL --retry 2 --connect-timeout 20 -A "Remielle-Astral-installer" \
    -H "Accept: application/vnd.github+json" "$url" 2>/dev/null
}

# "<tag> <url>" of every launcher zip for this platform, newest release
# first.  Releases that carry only the Custom server are passed over.
launcher_assets() {
  grep -o '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]*"' |
    sed 's/.*"\([a-z]*:\/\/[^"]*\)"$/\1/' |
    grep -E "/remielle-astral-[^/]+-$PLATFORM\.zip$" |
    while IFS= read -r u; do t="${u%/*}"; printf '%s %s\n' "${t##*/}" "$u"; done
}

# Sets TAG, URL, SUMS_URL, ZIP_NAME and NEW_VERSION.
resolve_release() {
  local json list line
  json="$(releases_json)" || json=""
  list="$(printf '%s' "$json" | launcher_assets)"
  if [ -n "$want_tag" ]; then
    line="$(awk -v a="$want_tag" -v b="${want_tag#v}" '$1 == a || $1 == b || $1 == "v" b { print; exit }' <<<"$list")"
    [ -n "$line" ] || line="v${want_tag#v} https://github.com/$REPO/releases/download/v${want_tag#v}/remielle-astral-${want_tag#v}-$PLATFORM.zip"
  else
    line="$(head -1 <<<"$list")"
    if [ -z "$line" ]; then
      if [ -z "$json" ]; then
        die "$(T "Could not reach the release list of $REPO (offline, or GitHub's hourly limit). Try again later, or use --version TAG or --zip FILE." "เข้าถึงรายการ release ของ $REPO ไม่ได้ (ออฟไลน์ หรือเกินโควตา GitHub ต่อชั่วโมง) ลองใหม่ภายหลัง หรือใช้ --version TAG / --zip FILE")"
      fi
      die "$(T "No release of $REPO carries remielle-astral-*-$PLATFORM.zip yet." "ยังไม่มี release ของ $REPO ที่มี remielle-astral-*-$PLATFORM.zip")"
    fi
  fi
  TAG="${line%% *}"
  URL="${line#* }"
  SUMS_URL="${URL%/*}/SHA256SUMS"
  ZIP_NAME="${URL##*/}"
  NEW_VERSION="${ZIP_NAME#remielle-astral-}"
  NEW_VERSION="${NEW_VERSION%-"$PLATFORM".zip}"
}

download() { # url file
  if [ -t 2 ]; then
    curl -fL --retry 2 --connect-timeout 20 --progress-bar -o "$2" "$1"
  else
    curl -fsSL --retry 2 --connect-timeout 20 -o "$2" "$1"
  fi
}

# The zip against the SHA256SUMS line for its name; the launcher's own
# updater refuses the same way.
verify_sum() { # zip sums name
  local want have
  want="$(awk -v n="$3" '{ f = $2; sub(/^\*/, "", f) } f == n { print $1; exit }' "$2")"
  [ -n "$want" ] || die "$(T "SHA256SUMS has no line for $3; nothing was installed." "SHA256SUMS ไม่มีบรรทัดของ $3 จึงไม่ติดตั้ง")"
  have="$(sha256sum "$1" | cut -d' ' -f1)"
  [ "$want" = "$have" ] || die "$(T "$3 does not match its SHA256SUMS (damaged or altered download); nothing was installed." "$3 ไม่ตรงกับ SHA256SUMS (ไฟล์เสียหรือถูกแก้) จึงไม่ติดตั้ง")"
  SHA="$have"
}

# ----------------------------------------------------------- system checks --
# The package command for GTK 3 + WebKitGTK 4.1 on this distribution.
distro_hint() {
  local ids
  ids="$( (. /etc/os-release 2>/dev/null && echo " ${ID:-} ${ID_LIKE:-} ") )"
  case "$ids" in
    *" arch "*) echo "sudo pacman -S --needed gtk3 webkit2gtk-4.1" ;;
    *" debian "*|*" ubuntu "*) echo "sudo apt install libgtk-3-0 libwebkit2gtk-4.1-0" ;;
    *" fedora "*|*" rhel "*) echo "sudo dnf install gtk3 webkit2gtk4.1" ;;
    *suse*) echo "sudo zypper install libgtk-3-0 libwebkit2gtk-4_1-0" ;;
    *) echo "" ;;
  esac
}

check_libraries() { # exe
  local missing hint
  command -v ldd >/dev/null || return 0
  missing="$(ldd "$1" 2>/dev/null | awk '/not found/ { print $1 }' | sort -u | tr '\n' ' ')"
  if [ -z "$missing" ]; then
    ok "$(T "GTK 3 and WebKitGTK 4.1 are present" "มี GTK 3 และ WebKitGTK 4.1 แล้ว")"
    return 0
  fi
  warn "$(T "Missing libraries: $missing" "ขาดไลบรารี: $missing")"
  hint="$(distro_hint)"
  if [ -n "$hint" ]; then
    warn "$(T "Install them with:" "ติดตั้งด้วย:") $hint"
  else
    warn "$(T "Install GTK 3 and WebKitGTK 4.1 (webkit2gtk-4.1) from your distribution." "ติดตั้ง GTK 3 และ WebKitGTK 4.1 (webkit2gtk-4.1) จาก distro ของคุณ")"
  fi
}

check_optional() {
  command -v wine >/dev/null || note "$(T "wine is not installed: needed to start the game on Linux" "ยังไม่มี wine: ต้องใช้เปิดเกมบน Linux")"
  command -v git >/dev/null || note "$(T "git is not installed: needed only for the Official server and patch" "ยังไม่มี git: ใช้เฉพาะเซิร์ฟและแพตช์ Official")"
}

# ------------------------------------------------------------ menu entries --
setup_menu() {
  local exe="$DIR/remielle-astral" entry="$APP_DIR/$APP_ID.desktop"
  mkdir -p "$BIN_DIR" "$APP_DIR" "$ICON_DIR"
  if [ -e "$BIN_DIR/remielle-astral" ] && [ ! -L "$BIN_DIR/remielle-astral" ]; then
    warn "$(T "Left $BIN_DIR/remielle-astral alone: it is a file, not a link." "ไม่แตะ $BIN_DIR/remielle-astral เพราะเป็นไฟล์จริง ไม่ใช่ลิงก์")"
  else
    ln -sfn "$exe" "$BIN_DIR/remielle-astral" && ok "$BIN_DIR/remielle-astral"
  fi
  [ -f "$DIR/icon.png" ] && cp "$DIR/icon.png" "$ICON_DIR/$APP_ID.png"
  # An entry from a source build (zig build menu) points elsewhere: kept.
  if [ -f "$entry" ] && ! grep -qF -- "$DIR" "$entry"; then
    mkdir -p "$DIR/.remielle-cache/old-menu-entries"
    cp "$entry" "$DIR/.remielle-cache/old-menu-entries/$APP_ID.desktop.$(date +%Y%m%d-%H%M%S)"
    note "$(T "The previous menu entry pointed elsewhere; a copy is in .remielle-cache/old-menu-entries" "เมนูเดิมชี้ไปที่อื่น เก็บสำเนาไว้ใน .remielle-cache/old-menu-entries")"
  fi
  # No prime-run: the launcher draws on the GPU that drives the screen (on a
  # hybrid laptop the NVIDIA one would leave the window blank).
  cat >"$entry" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Remielle Astral
GenericName=Zenless Zone Zero Launcher
Comment=Remielle (Zenless Zone Zero) server launcher
Exec="$exe"
Path=$DIR
Icon=$APP_ID
Terminal=false
Categories=Game;
Keywords=game;zenless;zzz;remielle;astral;server;launcher;
StartupWMClass=$APP_ID
StartupNotify=true
DESKTOP
  chmod 644 "$entry"
  if command -v kbuildsycoca6 >/dev/null; then kbuildsycoca6 >/dev/null 2>&1
  elif command -v kbuildsycoca5 >/dev/null; then kbuildsycoca5 >/dev/null 2>&1
  fi
  command -v update-desktop-database >/dev/null && update-desktop-database "$APP_DIR" >/dev/null 2>&1
  command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -f -t "$DATA_HOME/icons/hicolor" >/dev/null 2>&1
  ok "$(T "Application menu entry (Games)" "เพิ่มในเมนูแอป (หมวด Games)")"
  case ":${PATH:-}:" in
    *":$BIN_DIR:"*) ;;
    *) note "$(T "$BIN_DIR is not in PATH; start it from the menu, or add that folder to PATH." "$BIN_DIR ไม่อยู่ใน PATH เปิดจากเมนูแทน หรือเพิ่มโฟลเดอร์นี้ใน PATH")" ;;
  esac
}

offer_launch() {
  [ "$launch" = 1 ] || return 0
  [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] || return 0
  ask "$(T "Start Remielle Astral now?" "เปิด Remielle Astral เลยไหม?")" y || return 0
  # 9>&-: the child must not inherit the operation lock, or every later
  # install/uninstall reports "another install is running" while it lives.
  (cd "$DIR" && setsid -f "$DIR/remielle-astral" >/dev/null 2>&1 </dev/null 9>&-) ||
    (cd "$DIR" && nohup "$DIR/remielle-astral" >/dev/null 2>&1 </dev/null 9>&- &)
}

# ------------------------------------------------------------------- modes --
do_check() {
  local have
  have="$(version_in "$DIR")"
  resolve_release
  say "Remielle Astral"
  note "$(T "Installed:" "ที่ติดตั้ง:") ${have:-$(T "not installed" "ยังไม่ได้ติดตั้ง")} ($DIR)"
  note "$(T "Newest:" "ใหม่สุด:") $NEW_VERSION ($TAG)"
  if [ -n "$have" ] && ver_gt "$NEW_VERSION" "$have"; then
    ok "$(T "An update is available: run this installer again." "มีอัพเดท: รันตัวติดตั้งนี้อีกครั้ง")"
  elif [ -n "$have" ]; then
    ok "$(T "Up to date." "เป็นรุ่นล่าสุดแล้ว")"
  fi
}

do_rollback() {
  local prev="$DIR/.remielle-cache/previous" v now copy
  [ -f "$prev/remielle-astral" ] || die "$(T "There is no earlier version to put back." "ไม่มีรุ่นก่อนหน้าให้ย้อนกลับ")"
  v="$(version_in "$prev")"
  now="$(version_in "$DIR")"
  ask "$(T "Put back ${v:-the previous version} in place of ${now:-the installed one}?" "ย้อนกลับเป็น ${v:-รุ่นก่อนหน้า} แทน ${now:-รุ่นที่ติดตั้งอยู่} ไหม?")" y || return 0
  stop_launcher
  copy="$TMP/previous"
  cp -a "$prev" "$copy" || die "cannot copy $prev"
  install_from "$copy"
  write_info "${v:-unknown}" "" "rollback" ""
  ok "$(T "Rolled back to ${v:-the previous version}; --rollback again undoes it." "ย้อนกลับเป็น ${v:-รุ่นก่อนหน้า} แล้ว รัน --rollback อีกครั้งเพื่อกลับ")"
}

do_install() {
  local have zip sums root built
  have="$(version_in "$DIR")"

  if [ -n "$zip_file" ]; then
    [ -f "$zip_file" ] || die "$zip_file does not exist"
    ZIP_NAME="$(basename "$zip_file")"
    case "$ZIP_NAME" in
      remielle-astral-*-"$PLATFORM".zip) ;;
      *) die "$(T "$ZIP_NAME is not a Remielle Astral zip for $PLATFORM." "$ZIP_NAME ไม่ใช่ zip ของ Remielle Astral สำหรับ $PLATFORM")" ;;
    esac
    TAG=""
    URL="file://$(cd "$(dirname "$zip_file")" && pwd)/$ZIP_NAME"
    NEW_VERSION="${ZIP_NAME#remielle-astral-}"
    NEW_VERSION="${NEW_VERSION%-"$PLATFORM".zip}"
  else
    say "$(T "Looking up releases of $REPO" "ตรวจ release ของ $REPO")"
    resolve_release
  fi

  if [ -z "$have" ] && [ -e "$DIR/remielle-astral" ]; then
    note "$(T "Installed: an older build  →  $NEW_VERSION" "ที่ติดตั้ง: รุ่นเก่า  →  $NEW_VERSION")"
  elif [ -n "$have" ]; then
    note "$(T "Installed:" "ที่ติดตั้ง:") $have  →  $NEW_VERSION"
    # A release whose files were replaced keeps its number but is another
    # build: the checksums tell them apart.
    local installed_sha release_sha=""
    installed_sha="$(sed -n 's/^sha256=//p' "$DIR/.install-info" 2>/dev/null | head -1)"
    if [ -n "$zip_file" ]; then
      release_sha="$(sha256sum "$zip_file" | cut -d' ' -f1)"
    elif curl -fsSL --retry 2 --connect-timeout 20 -o "$TMP/SHA256SUMS" "$SUMS_URL" 2>/dev/null; then
      release_sha="$(awk -v n="$ZIP_NAME" '{ f = $2; sub(/^\*/, "", f) } f == n { print $1; exit }' "$TMP/SHA256SUMS")"
    fi
    if [ "$have" = "$NEW_VERSION" ] && [ "$force" = 0 ] && [ -n "$installed_sha" ] && [ -n "$release_sha" ] && [ "$installed_sha" != "$release_sha" ]; then
      note "$(T "Same version number, but the release holds a different build: installing it." "เลขเวอร์ชันเดิม แต่ไฟล์ใน release เป็น build ใหม่: ติดตั้งให้")"
    elif [ "$have" = "$NEW_VERSION" ] && [ "$force" = 0 ]; then
      if ! ask "$(T "$have is already installed. Reinstall it?" "ติดตั้ง $have อยู่แล้ว ติดตั้งซ้ำไหม?")" n; then
        ok "$(T "Already up to date; nothing changed." "เป็นรุ่นล่าสุดอยู่แล้ว ไม่ได้เปลี่ยนอะไร")"
        return 0
      fi
    elif ver_gt "$have" "$NEW_VERSION" && [ "$force" = 0 ]; then
      ask "$(T "$NEW_VERSION is older than the installed $have. Install it anyway?" "$NEW_VERSION เก่ากว่า $have ที่ติดตั้งอยู่ ติดตั้งต่อไหม?")" n || return 0
    fi
  fi

  zip="$TMP/$ZIP_NAME"
  sums="$TMP/SHA256SUMS"
  if [ -n "$zip_file" ]; then
    cp "$zip_file" "$zip" || die "cannot read $zip_file"
    if [ -f "$(dirname "$zip_file")/SHA256SUMS" ]; then
      cp "$(dirname "$zip_file")/SHA256SUMS" "$sums"
    else
      note "$(T "SHA256SUMS is not beside the zip; fetching it from release v$NEW_VERSION." "ไม่พบ SHA256SUMS ข้างไฟล์ กำลังโหลดจาก release v$NEW_VERSION")"
      download "https://github.com/$REPO/releases/download/v$NEW_VERSION/SHA256SUMS" "$sums" 2>/dev/null ||
        die "$(T "The local zip cannot be verified. Put SHA256SUMS beside it, then try again." "ตรวจสอบ zip ไม่ได้ ให้วาง SHA256SUMS ไว้ข้างไฟล์แล้วลองใหม่")"
    fi
    verify_sum "$zip" "$sums" "$ZIP_NAME"
    ok "SHA256 ✓"
  else
    say "$(T "Downloading" "ดาวน์โหลด") $ZIP_NAME"
    download "$URL" "$zip" || die "$(T "Download failed:" "ดาวน์โหลดไม่สำเร็จ:") $URL"
    download "$SUMS_URL" "$sums" 2>/dev/null ||
      die "$(T "The release has no SHA256SUMS, so the download cannot be checked; nothing was installed." "release นี้ไม่มี SHA256SUMS ตรวจไฟล์ไม่ได้ จึงไม่ติดตั้ง")"
    verify_sum "$zip" "$sums" "$ZIP_NAME"
    ok "SHA256 ✓"
  fi

  unzip -q -o "$zip" -d "$TMP/unpacked" || die "$(T "The zip could not be unpacked." "แตก zip ไม่ได้")"
  root="$(find "$TMP/unpacked" -maxdepth 2 -type f -name remielle-astral -print -quit)"
  [ -n "$root" ] || die "$(T "The zip holds no remielle-astral program." "ใน zip ไม่มีโปรแกรม remielle-astral")"
  root="$(dirname "$root")"
  is_elf "$root/remielle-astral" || die "$(T "remielle-astral in the zip is not a Linux program." "remielle-astral ใน zip ไม่ใช่โปรแกรม Linux")"
  chmod +x "$root/remielle-astral"
  built="$(version_in "$root")"
  [ -n "$built" ] && NEW_VERSION="$built"
  check_libraries "$root/remielle-astral"

  stop_launcher
  say "$(T "Installing" "ติดตั้ง") $NEW_VERSION → $DIR"
  install_from "$root"
  write_info "$NEW_VERSION" "$TAG" "$URL" "$SHA"
  ok "$(T "Program files replaced; settings, saves and mods kept" "แทนที่ไฟล์โปรแกรมแล้ว การตั้งค่า เซฟ และม็อดยังอยู่ครบ")"
  [ -d "$DIR/.remielle-cache/previous" ] && note "$(T "The replaced version is kept for: install.sh --rollback" "เก็บรุ่นเดิมไว้สำหรับ: install.sh --rollback")"

  [ "$menu" = 1 ] && setup_menu
  check_optional

  printf '\n%s%s%s\n' "$G$B" "$(T "Remielle Astral $NEW_VERSION is installed." "ติดตั้ง Remielle Astral $NEW_VERSION เรียบร้อย")" "$N"
  printf '%s\n' "$(T "This is a demo build: if you find a bug, please report it on Discord (the link is in the launcher)." "รุ่นนี้ยังเป็นเดโม ถ้าเจอบัคแจ้งทาง Discord ได้เลย (ลิงก์อยู่ในลันเชอร์)")"
  offer_launch
}

# -------------------------------------------------------------------- main --
main() {
  local tool
  while [ $# -gt 0 ]; do
    case "$1" in
      --version) [ $# -ge 2 ] || die "--version needs a tag"; want_tag="$2"; shift ;;
      --version=*) want_tag="${1#*=}" ;;
      --zip) [ $# -ge 2 ] || die "--zip needs a file"; zip_file="$2"; shift ;;
      --dir) [ $# -ge 2 ] || die "--dir needs a folder"; DIR="${2%/}"; shift ;;
      --check) mode="check" ;;
      --rollback) mode="rollback" ;;
      --force) force=1 ;;
      --no-menu) menu=0 ;;
      --no-launch) launch=0 ;;
      -y|--yes) yes=1 ;;
      -h|--help) usage; return 0 ;;
      *) die "unknown option: $1 (see --help)" ;;
    esac
    shift
  done

  case "${LANG:-}:${LC_MESSAGES:-}" in *th_*) thai=1 ;; esac
  grep -qs '"lang": *"th"' "$DIR/settings.json" && thai=1
  grep -qs '"lang": *"en"' "$DIR/settings.json" && thai=0

  { [ -n "${HOME:-}" ] && [ "$HOME" != "/" ]; } || die "HOME is not set"
  [ "$(uname -s)" = Linux ] || die "$(T "This installer is for Linux; on Windows use install.ps1." "ตัวติดตั้งนี้สำหรับ Linux บน Windows ใช้ install.ps1")"
  [ "$(uname -m)" = x86_64 ] || die "$(T "Remielle Astral is built for x86_64 only (this is $(uname -m))." "Remielle Astral มีเฉพาะ x86_64 (เครื่องนี้เป็น $(uname -m))")"
  for tool in curl unzip sha256sum; do
    command -v "$tool" >/dev/null || die "$(T "$tool is needed; install it with your package manager." "ต้องมี $tool ติดตั้งด้วยตัวจัดการแพ็กเกจของ distro")"
  done

  if command -v flock >/dev/null; then
    # Containers and restricted desktops can expose XDG_RUNTIME_DIR but mount
    # it read-only.  That is not a competing installer, so fall back to a
    # per-user lock in the real temporary directory before reporting busy.
    if ! { exec 9>"$LOCK_FILE"; } 2>/dev/null; then
      LOCK_FILE="${TMPDIR:-/tmp}/remielle-astral-op-${UID:-$(id -u)}.lock"
      exec 9>"$LOCK_FILE" || die "$(T "Cannot create the installer lock file." "สร้างไฟล์ล็อกสำหรับติดตั้งไม่ได้")"
    fi
    flock -n 9 || die "$(T "Another install or uninstall of Remielle Astral is running." "มีการติดตั้งหรือถอนการติดตั้ง Remielle Astral ทำงานอยู่แล้ว")"
  fi
  TMP="$(mktemp -d "${TMPDIR:-/tmp}/remielle-astral-install.XXXXXX")" || die "cannot create a temporary folder"
  trap 'rm -rf "$TMP"' EXIT

  case "$mode" in
    check) do_check ;;
    rollback) do_rollback ;;
    *) do_install ;;
  esac
}

main "$@"
