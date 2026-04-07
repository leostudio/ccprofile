# shellcheck shell=bash
# ccprofile rm <name>
#
# Safely delete a profile directory. Requires confirmation.
# Does not touch ~/.claude/ or the Keychain.

cmd_rm() {
  local name="" force="no"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -f|--force) force="yes"; shift ;;
      -h|--help)
        cat <<'EOF'
Usage: ccprofile rm <name> [-f|--force]

Delete a profile directory (e.g., ~/.claude-<name>/).

Does NOT remove:
  - The default profile at ~/.claude/
  - Keychain entries (run 'claude-<name> /logout' first to clean those)
EOF
        return 0 ;;
      -*) die "Unknown flag: $1" ;;
      *)
        [[ -z "$name" ]] || die "Multiple profile names given"
        name="$1"; shift
        ;;
    esac
  done

  [[ -n "$name" ]] || die "Profile name required"
  validate_profile_name "$name"

  local profile
  profile=$(profile_dir "$name")

  [[ -d "$profile" ]] || die "Profile not found: $profile"

  warn "About to delete: $profile"
  info ""
  info "Contents:"
  ls -la "$profile" | sed 's/^/  /'
  info ""

  hint "Note: Keychain OAuth tokens for this profile are not removed."
  hint "      If you want to revoke them, first run:"
  hint "        CLAUDE_CONFIG_DIR=$profile claude /logout"
  hint "      then re-run 'ccprofile rm $name'."
  info ""

  if [[ "$force" != "yes" ]]; then
    printf 'Delete this profile? [y/N] '
    local reply
    read -r reply
    [[ "$reply" =~ ^[Yy]$ ]] || { info "Aborted."; return 0; }
  fi

  rm -rf "$profile"
  ok "Deleted $profile"
}
