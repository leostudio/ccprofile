#!/usr/bin/env bash
#
# ccprofile installer — symlinks bin/ccprofile into ~/.local/bin/
# Does not modify shell configs (user adds aliases manually).
set -euo pipefail

SCRIPT_DIR=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TARGET_DIR="${CCPROFILE_INSTALL_DIR:-$HOME/.local/bin}"
TARGET_LINK="$TARGET_DIR/ccprofile"

mkdir -p "$TARGET_DIR"

if [[ -e "$TARGET_LINK" ]] && [[ ! -L "$TARGET_LINK" ]]; then
  printf 'ERROR: %s exists and is not a symlink. Refusing to overwrite.\n' "$TARGET_LINK" >&2
  exit 1
fi

ln -sf "$SCRIPT_DIR/bin/ccprofile" "$TARGET_LINK"
chmod +x "$SCRIPT_DIR/bin/ccprofile"

printf 'Installed: %s → %s\n' "$TARGET_LINK" "$SCRIPT_DIR/bin/ccprofile"

case ":$PATH:" in
  *":$TARGET_DIR:"*)
    printf 'PATH check: OK\n'
    ;;
  *)
    printf '\nWARNING: %s is not in your PATH.\n' "$TARGET_DIR"
    printf 'Add this to your ~/.zshrc or ~/.bashrc:\n\n'
    printf '  export PATH="%s:$PATH"\n\n' "$TARGET_DIR"
    ;;
esac

printf '\nRun: ccprofile help\n'
