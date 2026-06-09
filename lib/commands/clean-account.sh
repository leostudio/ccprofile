# shellcheck shell=bash
# ccprofile clean-account [default|<name>]
#
# Remove Claude Code account identity and auth-adjacent local state while
# preserving project/history/toolchain content.

clean_account_usage() {
  cat <<'EOF'
Usage: ccprofile clean-account [default|<name>] [flags]

Clean account-local Claude Code state for a profile.

Default mode is a dry run. Pass --apply to make changes.

Flags:
  --apply                 Backup and clean files
  --no-keychain           Do not delete matching macOS Keychain entries
  -f, --force             Do not ask for confirmation with --apply
  --backup-dir <dir>      Use a specific backup directory
  -h, --help              Show this help

What is cleaned:
  - account/subscription/cache keys inside .claude.json
  - legacy/custom OAuth config JSON variants, cleaned field-by-field
  - .credentials.json and legacy account config files
  - auth-adjacent caches such as statsig/, telemetry/, usage-data/
  - ide/*.lock local editor bridge tokens
  - teams/ is quarantined if present

What is preserved:
  - projects/, history.jsonl, file-history/, CLAUDE.md
  - rules/, skills/, commands/, plugins/
  - settings.json and generic cache/

Keychain entries are account credentials and are deleted by default with
--apply. They cannot be backed up; use --no-keychain to preserve them.
EOF
}

_clean_account_backup_file() {
  local src="$1" backup_dir="$2" label="$3"
  [[ -e "$src" ]] || return 0

  mkdir -p "$backup_dir"

  local dest="$backup_dir/$label"
  local n=1
  while [[ -e "$dest" ]]; do
    dest="$backup_dir/$label.$n"
    n=$((n + 1))
  done

  cp -p "$src" "$dest"
}

_clean_account_move_to_backup() {
  local src="$1" backup_dir="$2" rel="${3:-}"
  [[ -e "$src" ]] || return 0

  mkdir -p "$backup_dir"

  local base dest n
  base=$(basename "$src")
  [[ -n "$rel" ]] || rel="$base"
  dest="$backup_dir/$rel"
  mkdir -p "$(dirname "$dest")"
  n=1
  while [[ -e "$dest" ]]; do
    dest="$backup_dir/$rel.$n"
    n=$((n + 1))
  done

  mv "$src" "$dest"
  ok "Moved $rel to backup"
}

_clean_account_json() {
  local file="$1" backup_dir="$2" label="$3" apply="$4"
  [[ -f "$file" ]] || return 0

  if [[ "$apply" != "yes" ]]; then
    info "Would clean JSON: $file"
    return 0
  fi

  _clean_account_backup_file "$file" "$backup_dir" "$label"

  python3 - "$file" "${ACCOUNT_JSON_CLEAN_KEYS[@]}" -- "${PROJECT_JSON_CLEAN_KEYS[@]}" <<'PY'
import json
import os
import sys
import tempfile

path = sys.argv[1]
args = sys.argv[2:]
separator = args.index("--")
account_keys = args[:separator]
project_keys = args[separator + 1:]

with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)

if not isinstance(data, dict):
    raise SystemExit(f"{path} is not a JSON object")

for key in account_keys:
    data.pop(key, None)

# Preserve project trust/MCP settings, but remove per-account/session usage
# metrics that Claude Code reports on the next startup.
projects = data.get("projects")
if isinstance(projects, dict):
    for project_config in projects.values():
        if isinstance(project_config, dict):
            for key in project_keys:
                project_config.pop(key, None)

# Keep the required config shape while removing previous local startup history.
data["numStartups"] = 0

directory = os.path.dirname(path) or "."
fd, tmp = tempfile.mkstemp(prefix=".ccprofile-clean-", dir=directory)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    os.replace(tmp, path)
except Exception:
    try:
        os.unlink(tmp)
    except OSError:
        pass
    raise
PY

  ok "Cleaned JSON: $file"
}

_clean_account_json_variants() {
  local base_dir="$1" backup_dir="$2" label_prefix="$3" apply="$4"
  local suffix file label

  for suffix in "" "-custom-oauth" "-staging-oauth" "-local-oauth"; do
    file="$base_dir/.claude${suffix}.json"
    label="${label_prefix}-.claude${suffix}.json"
    _clean_account_json "$file" "$backup_dir" "$label" "$apply"
    _clean_account_json "$file.backup" "$backup_dir" "$label.backup" "$apply"
  done

  _clean_account_json "$base_dir/.config.json" "$backup_dir" "$label_prefix-.config.json" "$apply"
  _clean_account_json "$base_dir/.config.json.backup" "$backup_dir" "$label_prefix-.config.json.backup" "$apply"
}

_clean_account_dir_hash() {
  local config_dir="$1"
  printf '%s' "$config_dir" | shasum -a 256 | awk '{print substr($1, 1, 8)}'
}

_clean_account_keychain_services() {
  local profile="$1" config_dir="$2"
  local dir_hash=""
  if [[ "$profile" != "default" ]]; then
    dir_hash="-$(_clean_account_dir_hash "$config_dir")"
  fi

  # Production has no OAuth file suffix. Include the non-production suffixes too
  # so the cleanup remains correct when the same profile was used with staging,
  # local, or a custom OAuth URL.
  local oauth_suffix service_suffix
  for oauth_suffix in "" "-custom-oauth" "-staging-oauth" "-local-oauth"; do
    for service_suffix in "-credentials" ""; do
      printf 'Claude Code%s%s%s\n' "$oauth_suffix" "$service_suffix" "$dir_hash"
    done
  done
}

_clean_account_delete_keychain_items() {
  local profile="$1" config_dir="$2" apply="$3" clean_keychain="$4"

  if [[ "$clean_keychain" != "yes" ]]; then
    if [[ "$apply" == "yes" ]]; then
      warn "Keychain cleanup skipped by --no-keychain."
    else
      hint "Keychain cleanup would be skipped by --no-keychain."
    fi
    return 0
  fi

  if [[ "$(uname -s)" != "Darwin" ]] || ! command -v security >/dev/null 2>&1; then
    warn "Keychain cleanup skipped: macOS security CLI not available."
    return 0
  fi

  local username service
  username="${USER:-$(id -un 2>/dev/null || printf '')}"
  [[ -n "$username" ]] || { warn "Keychain cleanup skipped: cannot determine username."; return 0; }

  _clean_account_keychain_services "$profile" "$config_dir" | while IFS= read -r service; do
    [[ -n "$service" ]] || continue
    if [[ "$apply" != "yes" ]]; then
      info "Would delete Keychain item: $service"
      continue
    fi

    if security delete-generic-password -a "$username" -s "$service" >/dev/null 2>&1; then
      ok "Deleted Keychain item: $service"
    else
      hint "No Keychain item: $service"
    fi
  done
}

_clean_account_move_matching_backups() {
  local config_dir="$1" backup_dir="$2" apply="$3"
  local backups_dir="$config_dir/backups"
  [[ -d "$backups_dir" ]] || return 0

  local path
  for path in \
    "$backups_dir"/.claude*.json.backup* \
    "$backups_dir"/claude*.json.backup* \
    "$backups_dir"/.config.json.backup* \
    "$backups_dir"/config.json.backup*; do
    [[ -e "$path" ]] || continue
    if [[ "$apply" == "yes" ]]; then
      _clean_account_move_to_backup "$path" "$backup_dir" "backups/$(basename "$path")"
    else
      info "Would move to backup: $path"
    fi
  done
}

_clean_account_move_ide_locks() {
  local config_dir="$1" backup_dir="$2" apply="$3"
  local ide_dir="$config_dir/ide"
  [[ -d "$ide_dir" ]] || return 0

  local path
  for path in "$ide_dir"/*.lock; do
    [[ -e "$path" ]] || continue
    if [[ "$apply" == "yes" ]]; then
      _clean_account_move_to_backup "$path" "$backup_dir" "ide/$(basename "$path")"
    else
      info "Would move to backup: $path"
    fi
  done
}

cmd_clean_account() {
  local profile="default" apply="no" force="no" backup_dir="" clean_keychain="yes"
  local profile_given="no"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --apply)
        apply="yes"; shift ;;
      --keychain)
        # Backward compatible no-op: keychain cleanup is now the default.
        clean_keychain="yes"; shift ;;
      --no-keychain)
        clean_keychain="no"; shift ;;
      -f|--force)
        force="yes"; shift ;;
      --backup-dir)
        [[ $# -ge 2 ]] || die "--backup-dir requires a value"
        backup_dir="$2"; shift 2 ;;
      -h|--help)
        clean_account_usage
        return 0 ;;
      -*)
        die "Unknown flag: $1" ;;
      *)
        [[ "$profile_given" == "no" ]] || die "Multiple profile names given"
        profile="$1"; profile_given="yes"; shift ;;
    esac
  done

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

  [[ -d "$config_dir" ]] || die "Profile config dir not found: $config_dir"

  if [[ -z "$backup_dir" ]]; then
    backup_dir="$home/.claude_account_cleanup-$(date +%Y%m%d-%H%M%S)"
  fi

  info "Profile: $profile_label"
  info "Config dir: $config_dir"
  info "Backup dir: $backup_dir"
  info ""

  if [[ "$apply" != "yes" ]]; then
    warn "Dry run only. Re-run with --apply to clean."
  elif [[ "$force" != "yes" ]]; then
    warn "About to clean account-local state for: $profile_label"
    hint "This preserves project/history/toolchain content but removes account state."
    if [[ "$clean_keychain" == "yes" ]]; then
      hint "This also deletes matching macOS Keychain OAuth/API credentials."
    fi
    printf 'Continue? [y/N] '
    local reply
    read -r reply
    [[ "$reply" =~ ^[Yy]$ ]] || { info "Aborted."; return 0; }
  fi

  local json_backup_dir claude_backup_dir
  json_backup_dir="$backup_dir/json-originals"
  claude_backup_dir="$backup_dir/claude"

  if [[ "$profile" == "default" ]]; then
    _clean_account_json_variants "$home" "$json_backup_dir" "home" "$apply"
    _clean_account_json_variants "$config_dir" "$json_backup_dir" "config-dir" "$apply"
  else
    _clean_account_json_variants "$config_dir" "$json_backup_dir" "profile" "$apply"
  fi

  local item path
  for item in \
    ".credentials.json" \
    "config.json" \
    "${ISOLATED_AUTH_ADJACENT[@]}" \
    "daemon" \
    "daemon.lock" \
    "daemon.status.json" \
    ".last-update-result.json" \
    "teams"; do
    path="$config_dir/$item"
    if [[ "$apply" == "yes" ]]; then
      _clean_account_move_to_backup "$path" "$claude_backup_dir"
    elif [[ -e "$path" ]]; then
      info "Would move to backup: $path"
    fi
  done

  _clean_account_move_matching_backups "$config_dir" "$claude_backup_dir" "$apply"
  _clean_account_move_ide_locks "$config_dir" "$claude_backup_dir" "$apply"

  _clean_account_delete_keychain_items "$profile" "$config_dir" "$apply" "$clean_keychain"

  if [[ "$apply" == "yes" ]]; then
    ok "Account-local cleanup complete"
    hint "Backup: $backup_dir"
  else
    info ""
    hint "No changes made."
  fi
}
