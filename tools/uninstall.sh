#!/usr/bin/env bash
# Remielle Astral uninstaller for Linux.
#
#   curl -fsSL https://raw.githubusercontent.com/thaxao/Remielle-Astral/main/tools/uninstall.sh | bash
#   curl -fsSL .../uninstall.sh | bash -s -- --purge
#
# By default only the program goes: its files (the release's MANIFEST), the
# ~/.local/bin link and the menu entry.  settings.json, the Custom server and
# its saves, the save backups, the caches and the mod library stay, so a later
# install carries on where this one stopped.
#
# Options
#   --purge        remove those too.  settings.json, the saves and the save
#                  backups are packed into ~/Remielle-Astral-backup-<date>.tar.gz
#                  first; the mod library is only removed when you say so
#   --with-mods    with --purge: remove the mod library without asking
#   --no-backup    with --purge: no archive
#   --dry-run      show what would be removed and change nothing
#   --dir DIR      the install folder (default ~/.local/share/remielle-astral)
#   -y, --yes      answer every question with its default
#
# The game client and an Official server checkout live in folders of your
# own and are never touched.

# Nothing runs until `main "$@"` on the last line, so a download cut short by
# the network never runs half a script.

set -uo pipefail
export LC_ALL=C

DATA_HOME="${XDG_DATA_HOME:-${HOME:-}/.local/share}"
DIR="$DATA_HOME/remielle-astral"
BIN_LINK="${HOME:-}/.local/bin/remielle-astral"
APP_ID="io.github.thaxao.RemielleAstral"
ENTRY="$DATA_HOME/applications/$APP_ID.desktop"
ICON="$DATA_HOME/icons/hicolor/256x256/apps/$APP_ID.png"
LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/remielle-astral-op.lock"

LEGACY_FILES="remielle-astral remielle-astral.old README.md LICENSE icon.png MANIFEST
tools/remielle-update tools/build-official-patch tools/import-patch
tools/install.sh tools/install.ps1 tools/install.cmd
tools/uninstall.sh tools/uninstall.ps1 tools/uninstall.cmd
patch/Pryce.exe patch/Armorer.dll"
# The mod library's parts when it lives in the install folder (the default).
MOD_PARTS="xxmi mods.json staging quarantine backups cache"

purge=0 with_mods=0 backup=1 dry=0 yes=0 thai=0

# ------------------------------------------------------------------ output --
if [ -t 1 ]; then
  B=$'\033[1m' G=$'\033[32m' C=$'\033[36m' Y=$'\033[33m' R=$'\033[31m' D=$'\033[2m' N=$'\033[0m'
else
  B="" G="" C="" Y="" R="" D="" N=""
fi
T() { if [ "$thai" = 1 ] && [ -n "${2:-}" ]; then printf '%s' "$2"; else printf '%s' "$1"; fi; }
say()  { printf '%s==>%s %s%s%s\n' "$C" "$N" "$B" "$*" "$N"; }
ok()   { printf '  %s✓%s %s\n' "$G" "$N" "$*"; }
note() { printf '  %s·%s %s\n' "$D" "$N" "$*"; }
warn() { printf '  %s!%s %s\n' "$Y" "$N" "$*" >&2; }
die()  { printf '%serror:%s %s\n' "$R" "$N" "$*" >&2; exit 1; }
# A step that happened (quiet in a dry run, which only lists).
did()  { [ "$dry" = 1 ] || ok "$@"; }

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
Remielle Astral uninstaller for Linux

  uninstall.sh              remove the program; keep settings, saves, caches and mods
  uninstall.sh --purge      remove those too (settings and saves are archived to ~ first)

  --with-mods   with --purge: remove the mod library without asking
  --no-backup   with --purge: do not keep the archive
  --dry-run     show what would be removed, change nothing
  --dir DIR     install folder (default ~/.local/share/remielle-astral)
  -y, --yes     answer every question with its default
EOF
}

size_of() { du -sh "$@" 2>/dev/null | awk '{ print $1 }' | head -1; }

# Deletes $1 (inside the install folder, or one of the launcher's own menu
# files), or only says so with --dry-run.
remove() {
  case "$1" in
    "$DIR"/*|"$BIN_LINK"|"$ENTRY"|"$ICON"|"$DATA_HOME/$APP_ID") ;;
    *) warn "refusing to remove $1"; return 1 ;;
  esac
  [ -e "$1" ] || [ -L "$1" ] || return 0
  if [ "$dry" = 1 ]; then
    note "$(T "would remove" "จะลบ") $1"
  else
    rm -rf -- "$1"
  fi
}

safe_paths() { grep -v -e '^/' -e '^$' -e '\(^\|/\)\.\.\(/\|$\)' || true; }

program_files() {
  {
    [ -f "$DIR/MANIFEST" ] && tr -d '\r' <"$DIR/MANIFEST"
    # shellcheck disable=SC2086
    printf '%s\n' $LEGACY_FILES .install-info
  } | safe_paths | LC_ALL=C sort -u
}

pids_under() { # prefix: processes whose program lives under that folder
  local p exe
  for p in /proc/[0-9]*; do
    exe="$(readlink "$p/exe" 2>/dev/null)" || continue
    case "$exe" in "$1"/*) printf '%s\n' "${p#/proc/}" ;; esac
  done
}

stop_pids() { # what pids...
  local what="$1" left="" p
  shift
  [ $# -gt 0 ] || return 0
  if [ "$dry" = 1 ]; then
    note "$(T "would close $what (pid $*)" "จะปิด $what (pid $*)")"
    return 0
  fi
  kill "$@" 2>/dev/null
  for _ in $(seq 1 50); do
    left=""
    for p in "$@"; do [ -e "/proc/$p" ] && left="$left $p"; done
    [ -n "$left" ] || break
    sleep 0.1
  done
  # shellcheck disable=SC2086
  [ -n "$left" ] && kill -9 $left 2>/dev/null
  did "$(T "Closed $what" "ปิด $what แล้ว")"
}

setting() { # key: a string value from settings.json
  sed -n "s/^ *\"$1\": *\"\\(.*\\)\",\\{0,1\\}$/\\1/p" "$DIR/settings.json" 2>/dev/null | head -1
}

# -------------------------------------------------------------------- main --
main() {
  local real launcher_pids server_pids f kept archive parts mods_here
  while [ $# -gt 0 ]; do
    case "$1" in
      --purge) purge=1 ;;
      --with-mods) with_mods=1 ;;
      --no-backup) backup=0 ;;
      --dry-run) dry=1 ;;
      --dir) [ $# -ge 2 ] || die "--dir needs a folder"; DIR="${2%/}"; shift ;;
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
  case "$DIR" in
    ""|/|"$HOME"|"$DATA_HOME"|"$HOME/.local"|/usr*|/etc*|/bin*|/lib*) die "refusing to work on $DIR" ;;
  esac

  local has_program=0 has_link=0 has_entry=0
  { [ -e "$DIR/remielle-astral" ] || [ -f "$DIR/MANIFEST" ] || [ -f "$DIR/.install-info" ]; } && has_program=1
  [ -L "$BIN_LINK" ] && case "$(readlink "$BIN_LINK")" in "$DIR"/*) has_link=1 ;; esac
  [ -f "$ENTRY" ] && grep -qF -- "$DIR" "$ENTRY" && has_entry=1
  if [ "$has_program" = 0 ] && [ "$has_link" = 0 ] && [ "$has_entry" = 0 ] && { [ "$purge" = 0 ] || [ ! -d "$DIR" ]; }; then
    say "$(T "Remielle Astral is not installed in $DIR." "ไม่พบ Remielle Astral ใน $DIR")"
    return 0
  fi
  if [ -d "$DIR" ] && [ ! -e "$DIR/remielle-astral" ] && [ ! -f "$DIR/settings.json" ] && [ ! -f "$DIR/.install-info" ] && [ ! -f "$DIR/MANIFEST" ] && [ ! -d "$DIR/xxmi" ]; then
    die "$(T "$DIR does not look like a Remielle Astral folder; nothing was removed." "$DIR ไม่ใช่โฟลเดอร์ของ Remielle Astral จึงไม่ลบอะไร")"
  fi

  if command -v flock >/dev/null; then
    { exec 9>"$LOCK_FILE" && flock -n 9; } ||
      die "$(T "Another install or uninstall of Remielle Astral is running." "มีการติดตั้งหรือถอนการติดตั้ง Remielle Astral ทำงานอยู่แล้ว")"
  fi

  real="$DIR"
  [ -d "$DIR" ] && real="$(cd "$DIR" && pwd -P)"

  # ---- the plan
  say "$(T "Uninstalling Remielle Astral" "ถอนการติดตั้ง Remielle Astral") ($DIR)"
  [ "$dry" = 1 ] && note "$(T "dry run: nothing is changed" "ทดลองดู: ไม่มีอะไรถูกเปลี่ยน")"
  note "$(T "Program:" "โปรแกรม:") $(T "removed" "ลบ")"
  mods_here=""
  for f in $MOD_PARTS; do [ -e "$DIR/$f" ] && mods_here="$mods_here $f"; done
  local line
  for line in \
    "settings.json|$(T "settings" "การตั้งค่า")" \
    "remielle-server|$(T "Custom server and its saves (Persistent)" "เซิร์ฟ Custom และเซฟ (Persistent)")" \
    ".remielle-cache|$(T "save backups, pictures and caches" "สำรองเซฟ รูป และแคช")"; do
    f="${line%%|*}"
    [ -e "$DIR/$f" ] || continue
    if [ "$purge" = 1 ]; then
      note "$f ($(size_of "$DIR/$f")): $(T "removed" "ลบ") — ${line#*|}"
    else
      note "$f ($(size_of "$DIR/$f")): $(T "kept" "เก็บไว้") — ${line#*|}"
    fi
  done
  if [ -n "$mods_here" ]; then
    # shellcheck disable=SC2086
    local mods_fate
    mods_fate="$(T "kept unless you say otherwise" "เก็บไว้ ถ้าไม่สั่งลบ")"
    [ "$purge" = 1 ] && [ "$with_mods" = 1 ] && mods_fate="$(T "removed" "ลบ")"
    note "$(T "mod library" "คลังม็อด") ($(cd "$DIR" && du -shc $mods_here 2>/dev/null | tail -1 | awk '{ print $1 }')): $mods_fate"
  fi
  local server_dir client_dir
  server_dir="$(setting server_dir)"
  client_dir="$(setting client_dir)"
  [ -n "$server_dir" ] && note "$(T "Official server folder, not touched:" "โฟลเดอร์เซิร์ฟ Official ไม่แตะ:") $server_dir"
  [ -n "$client_dir" ] && note "$(T "Game client folder, not touched:" "โฟลเดอร์เกม ไม่แตะ:") $client_dir"

  if [ "$purge" = 1 ]; then
    ask "$(T "Remove Remielle Astral and its data?" "ลบ Remielle Astral และข้อมูลทั้งหมดไหม?")" y || { ok "$(T "Cancelled." "ยกเลิกแล้ว")"; return 0; }
  else
    ask "$(T "Remove the program (your data stays)?" "ลบโปรแกรม (ข้อมูลยังอยู่) ไหม?")" y || { ok "$(T "Cancelled." "ยกเลิกแล้ว")"; return 0; }
  fi
  local drop_mods=0
  if [ "$purge" = 1 ] && [ -n "$mods_here" ]; then
    if [ "$with_mods" = 1 ] || ask "$(T "Also delete the mod library (your mods)?" "ลบคลังม็อด (ม็อดของคุณ) ด้วยไหม?")" n; then drop_mods=1; fi
  fi

  # ---- close what runs from here
  launcher_pids="$(pids_under "$real" | while read -r p; do
    case "$(readlink "/proc/$p/exe" 2>/dev/null)" in "$real/remielle-astral"*) echo "$p" ;; esac
  done | tr '\n' ' ')"
  # shellcheck disable=SC2086
  stop_pids "Remielle Astral" $launcher_pids
  server_pids="$(pids_under "$real/remielle-server" | tr '\n' ' ')"
  if [ -n "${server_pids// /}" ]; then
    if [ "$purge" = 1 ] || ask "$(T "The Custom server is running (pid ${server_pids% }). Stop it?" "เซิร์ฟ Custom กำลังรัน (pid ${server_pids% }) หยุดไหม?")" y; then
      # shellcheck disable=SC2086
      stop_pids "$(T "the Custom server" "เซิร์ฟ Custom")" $server_pids
    fi
  fi

  # ---- archive before anything is deleted
  if [ "$purge" = 1 ] && [ "$backup" = 1 ]; then
    parts=""
    for f in settings.json remielle-server/Persistent .remielle-cache/backups mods.json; do
      [ -e "$DIR/$f" ] && parts="$parts $f"
    done
    if [ -n "$parts" ]; then
      archive="$HOME/Remielle-Astral-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
      if [ "$dry" = 1 ]; then
        note "$(T "would archive" "จะเก็บ")$parts → $archive"
      else
        # shellcheck disable=SC2086
        if ! { tar -czf "$archive" -C "$DIR" $parts 2>/dev/null && tar -tzf "$archive" >/dev/null 2>&1; }; then
          rm -f "$archive"
          die "$(T "Could not archive the saves to $archive; nothing was removed." "เก็บเซฟลง $archive ไม่สำเร็จ จึงไม่ลบอะไร")"
        fi
        ok "$(T "Saves and settings archived:" "เก็บเซฟและการตั้งค่าไว้ที่:") $archive ($(size_of "$archive"))"
      fi
    fi
  fi

  # ---- the program
  while IFS= read -r f; do
    remove "$DIR/$f"
  done < <(program_files)
  remove "$DIR/.remielle-cache/previous"
  for f in "$DIR"/*.astral-new "$DIR"/tools/*.astral-new; do [ -e "$f" ] && remove "$f"; done
  [ "$dry" = 1 ] || rmdir "$DIR/tools" "$DIR/patch" 2>/dev/null
  did "$(T "Program files removed" "ลบไฟล์โปรแกรมแล้ว")"

  # ---- the data, with --purge
  if [ "$purge" = 1 ]; then
    remove "$DIR/settings.json"
    remove "$DIR/remielle-server"
    remove "$DIR/.remielle-cache"
    remove "$DATA_HOME/$APP_ID"
    if [ "$drop_mods" = 1 ]; then
      for f in $MOD_PARTS; do remove "$DIR/$f"; done
    fi
    did "$(T "Data removed" "ลบข้อมูลแล้ว")"
  fi

  # ---- menu entries that are ours
  if [ -L "$BIN_LINK" ]; then
    case "$(readlink "$BIN_LINK")" in
      "$DIR"/*|"$real"/*) remove "$BIN_LINK" && did "$(T "Removed" "ลบ") $BIN_LINK" ;;
      *) note "$(T "Left $BIN_LINK: it points elsewhere" "ไม่แตะ $BIN_LINK เพราะชี้ไปที่อื่น") ($(readlink "$BIN_LINK"))" ;;
    esac
  fi
  if [ -f "$ENTRY" ]; then
    if grep -qF -- "$DIR" "$ENTRY" || grep -qF -- "$real" "$ENTRY"; then
      remove "$ENTRY"
      remove "$ICON"
      did "$(T "Menu entry removed" "ลบเมนูแอปแล้ว")"
    else
      note "$(T "Left the menu entry: it starts a Remielle Astral elsewhere" "ไม่แตะเมนูแอป เพราะเปิด Remielle Astral ที่อื่น") ($(sed -n 's/^Exec=//p' "$ENTRY" | head -1))"
    fi
  fi
  if [ "$dry" = 0 ]; then
    if command -v kbuildsycoca6 >/dev/null; then kbuildsycoca6 >/dev/null 2>&1
    elif command -v kbuildsycoca5 >/dev/null; then kbuildsycoca5 >/dev/null 2>&1
    fi
    command -v update-desktop-database >/dev/null && update-desktop-database "$DATA_HOME/applications" >/dev/null 2>&1
  fi

  # ---- what is left
  if [ "$dry" = 1 ]; then
    printf '\n%s\n' "$(T "Dry run finished: nothing was changed." "ทดลองเสร็จ: ไม่มีอะไรถูกเปลี่ยน")"
    return 0
  fi
  [ -d "$DIR" ] && rmdir "$DIR" 2>/dev/null
  printf '\n%s%s%s\n' "$G$B" "$(T "Remielle Astral is uninstalled." "ถอนการติดตั้ง Remielle Astral เรียบร้อย")" "$N"
  if [ -d "$DIR" ]; then
    kept="$(cd "$DIR" && ls -A 2>/dev/null | tr '\n' ' ')"
    if [ -n "$kept" ]; then
      printf '%s\n' "$(T "Kept in $DIR:" "ยังเก็บไว้ใน $DIR:") $kept"
      if [ "$purge" = 0 ]; then
        printf '%s\n' "$(T "Installing again picks these up. To remove them too: uninstall.sh --purge" "ติดตั้งใหม่จะใช้ข้อมูลเหล่านี้ต่อ ถ้าจะลบด้วย: uninstall.sh --purge")"
      else
        printf '%s\n' "$(T "The mod library was kept. To remove it too: uninstall.sh --purge --with-mods" "คลังม็อดยังอยู่ ถ้าจะลบด้วย: uninstall.sh --purge --with-mods")"
      fi
    fi
  fi
  return 0
}

main "$@"
