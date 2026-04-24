#!/bin/sh
set -eu

# Config directory (prefer XDG if set)
HYPR_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
TARGET="$HYPR_DIR/hyprland.conf"

die() { printf '%s\n' "Error: $*" >&2; exit 1; }
info() { printf '%s\n' "$*"; }

[ -d "$HYPR_DIR" ] || die "Hypr config dir not found: $HYPR_DIR"

# List *.conf files in HYPR_DIR (filenames only), excluding nothing by default.
# Avoid GNU find extensions; avoid -printf.
list_confs() {
  # Using find + basename is portable.
  find "$HYPR_DIR" -maxdepth 1 -type f -name '*.conf' 2>/dev/null \
    | sed 's|.*/||' \
    | sort
}

# Pick one config from list. Prints filename or empty if cancelled (fzf).
pick_conf() {
  CONFS="$(list_confs)"
  [ -n "$CONFS" ] || die "No .conf files found in $HYPR_DIR"

  if command -v fzf >/dev/null 2>&1; then
    # shellcheck disable=SC2086
    printf '%s\n' "$CONFS" | fzf --prompt="Hypr config> " --height=15 --border || true
    return 0
  fi

  info "Select a Hyprland config:"
  i=1
  # print menu
  echo "$CONFS" | while IFS= read -r f; do
    printf "  %2d) %s\n" "$i" "$f"
    i=$((i+1))
  done

  while :; do
    printf "Enter number (or 'q' to quit): "
    IFS= read -r ans || exit 0
    case "$ans" in
      q|Q) exit 0 ;;
      *[!0-9]*|'') info "Invalid input.\n" ;;
      *)
        # Get Nth line (portable via sed)
        choice="$(echo "$CONFS" | sed -n "${ans}p")"
        [ -n "$choice" ] && { printf '%s\n' "$choice"; return 0; }
        info "Out of range.\n"
        ;;
    esac
  done
}

prompt_action() {
  info "What do you want to do?\n"
  info "  1) Switch/apply a config (copy to hyprland.conf)\n"
  info "  2) Duplicate a config (create a new .conf based on it)\n"
  info "  q) Quit\n"
  printf "Choice: "
  IFS= read -r a || exit 0
  printf '%s\n' "$a"
}

backup_target() {
  if [ -f "$TARGET" ]; then
    ts="$(date +%Y%m%d-%H%M%S)"
    bk="$TARGET.bak.$ts"
    cp "$TARGET" "$bk" || die "Failed to backup $TARGET"
    info "Backed up current config to: $bk\n"
  fi
}

reload_hyprland_if_possible() {
  if command -v hyprctl >/dev/null 2>&1; then
    # Only reload if this looks like a Hyprland session
    if [ "${HYPRLAND_INSTANCE_SIGNATURE:-}" != "" ]; then
      hyprctl reload >/dev/null 2>&1 || true
      info "Hyprland reloaded.\n"
    else
      info "Note: Not in a Hyprland session; not reloading.\n"
    fi
  fi
}

switch_config() {
  sel="$(pick_conf)"
  [ -n "$sel" ] || { info "No selection made.\n"; exit 0; }

  src="$HYPR_DIR/$sel"
  [ -f "$src" ] || die "Selected file not found: $src"

  backup_target
  cp "$src" "$TARGET" || die "Failed to activate config"
  info "Activated: $sel -> hyprland.conf\n"
  reload_hyprland_if_possible
}

duplicate_config() {
  base="$(pick_conf)"
  [ -n "$base" ] || { info "No selection made.\n"; exit 0; }

  src="$HYPR_DIR/$base"
  [ -f "$src" ] || die "Selected file not found: $src"

  info "Enter new config name (without .conf). Example: laptop-copy\n"
  printf "Name: "
  IFS= read -r name || exit 0

  # Basic validation: non-empty, no slashes, no leading dot
  [ -n "$name" ] || die "Name cannot be empty"
  case "$name" in
    *'/'*) die "Name must not contain '/'" ;;
    .* ) die "Name must not start with '.'" ;;
  esac

  dest="$HYPR_DIR/$name.conf"
  if [ -e "$dest" ]; then
    die "File already exists: $dest"
  fi

  cp "$src" "$dest" || die "Failed to duplicate config"
  info "Created: $(basename "$dest") (from $base)\n"
}

main() {
  a="$(prompt_action)"
  case "$a" in
    1) switch_config ;;
    2) duplicate_config ;;
    q|Q) exit 0 ;;
    *) die "Unknown choice: $a" ;;
  esac
}

main "$@"
