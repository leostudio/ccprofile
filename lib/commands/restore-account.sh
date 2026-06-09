# shellcheck shell=bash
# ccprofile restore-account [default|<name>] --backup-dir <dir>
#
# Restore files created by `ccprofile clean-account`.

restore_account_usage() {
  cat <<'EOF'
Usage: ccprofile restore-account [default|<name>] --backup-dir <dir> [flags]

Restore account-local Claude Code state from a clean-account backup.

Default mode is a dry run. Pass --apply to make changes.

Flags:
  --apply                 Restore files
  -f, --force             Do not ask for confirmation with --apply
  --backup-dir <dir>      Backup directory created by clean-account
  -h, --help              Show this help

Notes:
  - Existing active files are first moved under restore-overwritten-*.
  - macOS Keychain credentials cannot be restored because clean-account cannot
    back up Keychain secrets.
EOF
}

_restore_account_backup_existing() {
  local dest="$1" rel="$2" overwrite_dir="$3" apply="$4"
  [[ -e "$dest" || -L "$dest" ]] || return 0

  if [[ "$apply" != "yes" ]]; then
    info "Would move existing active path aside: $dest"
    return 0
  fi

  local backup_dest
  backup_dest="$overwrite_dir/$rel"
  mkdir -p "$(dirname "$backup_dest")"

  local n=1
  while [[ -e "$backup_dest" || -L "$backup_dest" ]]; do
    backup_dest="$overwrite_dir/$rel.$n"
    n=$((n + 1))
  done

  mv "$dest" "$backup_dest"
  ok "Moved existing active path aside: $rel"
}

_restore_account_copy_path() {
  local src="$1" dest="$2" rel="$3" overwrite_dir="$4" apply="$5"
  [[ -e "$src" || -L "$src" ]] || return 0

  if [[ "$apply" != "yes" ]]; then
    info "Would restore: $dest"
    return 0
  fi

  _restore_account_backup_existing "$dest" "$rel" "$overwrite_dir" "$apply"
  mkdir -p "$(dirname "$dest")"

  if [[ -d "$src" && ! -L "$src" ]]; then
    mkdir -p "$dest"
  else
    cp -p "$src" "$dest"
  fi
  ok "Restored: $dest"
}

_restore_account_json_variants() {
  local base_dir="$1" json_backup_dir="$2" label_prefix="$3" overwrite_dir="$4" apply="$5"
  local suffix src dest label rel

  for suffix in "" "-custom-oauth" "-staging-oauth" "-local-oauth"; do
    label="${label_prefix}-.claude${suffix}.json"
    src="$json_backup_dir/$label"
    dest="$base_dir/.claude${suffix}.json"
    rel="json-originals/$label"
    _restore_account_copy_path "$src" "$dest" "$rel" "$overwrite_dir" "$apply"

    label="${label_prefix}-.claude${suffix}.json.backup"
    src="$json_backup_dir/$label"
    dest="$base_dir/.claude${suffix}.json.backup"
    rel="json-originals/$label"
    _restore_account_copy_path "$src" "$dest" "$rel" "$overwrite_dir" "$apply"
  done

  label="$label_prefix-.config.json"
  _restore_account_copy_path "$json_backup_dir/$label" "$base_dir/.config.json" "json-originals/$label" "$overwrite_dir" "$apply"

  label="$label_prefix-.config.json.backup"
  _restore_account_copy_path "$json_backup_dir/$label" "$base_dir/.config.json.backup" "json-originals/$label" "$overwrite_dir" "$apply"
}

_restore_account_claude_tree() {
  local claude_backup_dir="$1" config_dir="$2" overwrite_dir="$3" apply="$4"
  [[ -d "$claude_backup_dir" ]] || return 0

  local path rel dest
  while IFS= read -r -d '' path; do
    rel="${path#$claude_backup_dir/}"
    dest="$config_dir/$rel"
    _restore_account_copy_path "$path" "$dest" "claude/$rel" "$overwrite_dir" "$apply"
  done < <(find "$claude_backup_dir" -mindepth 1 -print0)
}

cmd_restore_account() {
  local profile="default" apply="no" force="no" backup_dir=""
  local profile_given="no"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --apply)
        apply="yes"; shift ;;
      -f|--force)
        force="yes"; shift ;;
      --backup-dir)
        [[ $# -ge 2 ]] || die "--backup-dir requires a value"
        backup_dir="$2"; shift 2 ;;
      -h|--help)
        restore_account_usage
        return 0 ;;
      -*)
        die "Unknown flag: $1" ;;
      *)
        [[ "$profile_given" == "no" ]] || die "Multiple profile names given"
        profile="$1"; profile_given="yes"; shift ;;
    esac
  done

  [[ -n "$backup_dir" ]] || die "--backup-dir is required"
  [[ -d "$backup_dir" ]] || die "Backup dir not found: $backup_dir"

  local home config_dir profile_label
  home=$(ccp_home)

  if [[ "$profile" == "default" ]]; then
    config_dir=$(main_claude_dir)
    profile_label="default"
  else
    validate_profile_name "$profile"
    config_dir=$(profile_dir "$profile")
    profile_label="$profile"
  fi

  mkdir -p "$config_dir"

  local json_backup_dir claude_backup_dir overwrite_dir
  json_backup_dir="$backup_dir/json-originals"
  claude_backup_dir="$backup_dir/claude"
  overwrite_dir="$backup_dir/restore-overwritten-$(date +%Y%m%d-%H%M%S)"

  info "Profile: $profile_label"
  info "Config dir: $config_dir"
  info "Backup dir: $backup_dir"
  info ""

  if [[ "$apply" != "yes" ]]; then
    warn "Dry run only. Re-run with --apply to restore."
  elif [[ "$force" != "yes" ]]; then
    warn "About to restore account-local state for: $profile_label"
    hint "Existing active files will be moved under: $overwrite_dir"
    hint "Keychain credentials cannot be restored from this backup."
    printf 'Continue? [y/N] '
    local reply
    read -r reply
    [[ "$reply" =~ ^[Yy]$ ]] || { info "Aborted."; return 0; }
  fi

  if [[ "$profile" == "default" ]]; then
    _restore_account_json_variants "$home" "$json_backup_dir" "home" "$overwrite_dir" "$apply"
    _restore_account_json_variants "$config_dir" "$json_backup_dir" "config-dir" "$overwrite_dir" "$apply"
  else
    _restore_account_json_variants "$config_dir" "$json_backup_dir" "profile" "$overwrite_dir" "$apply"
  fi

  _restore_account_claude_tree "$claude_backup_dir" "$config_dir" "$overwrite_dir" "$apply"

  if [[ "$apply" == "yes" ]]; then
    ok "Account-local restore complete"
    hint "Overwritten active files, if any: $overwrite_dir"
    warn "Keychain credentials were not restored; log in again if needed."
  else
    info ""
    hint "No changes made."
    hint "Keychain credentials cannot be restored from this backup."
  fi
}
