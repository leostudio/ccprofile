# shellcheck shell=bash
# ccprofile doctor <name>
#
# Health check: verify identity isolation and toolchain sharing.

cmd_doctor() {
  local name="$1"
  [[ -n "$name" ]] || die "Profile name required"
  [[ "$name" == "-h" || "$name" == "--help" ]] && {
    cat <<'EOF'
Usage: ccprofile doctor <name>

Verify profile health:
  - Identity files (.claude.json, .credentials.json) are independent
  - Auth-adjacent caches (statsig/, usage-data/, etc.) are independent
  - Concurrent-state dirs (sessions/, tasks/, debug/, log/) are independent
  - Toolchain files (skills/, plugins/, etc.) are symlinks with valid targets
  - No dangling symlinks
EOF
    return 0
  }

  validate_profile_name "$name"

  local main_dir profile
  main_dir=$(main_claude_dir)
  profile=$(profile_dir "$name")

  [[ -d "$profile" ]] || die "Profile not found: $profile"

  bold "Profile: "; printf '%s\n' "$name"
  info "Path: $profile"
  info ""

  local errors=0 warnings=0 item path

  info "$(bold "Identity isolation")"
  for item in "${ISOLATED_IDENTITY[@]}"; do
    path="$profile/$item"
    if [[ -L "$path" ]]; then
      err "  $item is a symlink — this breaks account isolation!"
      errors=$((errors + 1))
    elif [[ "$item" == "config.json" ]] && [[ -e "$path" ]]; then
      warn "  $item exists (legacy fallback — getGlobalClaudeFile will use this over .claude.json)"
      warnings=$((warnings + 1))
    elif [[ -e "$path" ]]; then
      ok "  $item is an independent file"
    else
      hint "  $item does not exist yet (run 'claude-$name' once)"
    fi
  done

  info ""
  info "$(bold "Auth-adjacent isolation") ${C_DIM}(key difference from other tools)${C_RESET}"
  _check_isolated_group "$profile" \
    "account-specific data will leak across profiles!" \
    "${ISOLATED_AUTH_ADJACENT[@]}"
  errors=$((errors + $?))

  info ""
  info "$(bold "Concurrent-run state")"
  _check_isolated_group "$profile" \
    "concurrent runs will collide on locks/PIDs!" \
    "${ISOLATED_CONCURRENT[@]}"
  errors=$((errors + $?))

  # Toolchain sharing
  info ""
  info "$(bold "Toolchain sharing")"
  local source_path
  for item in "${SHARED_TOOLCHAIN[@]}" "${SHARED_CACHES[@]}" "${SHARED_PERSONAL[@]}"; do
    path="$profile/$item"
    source_path="$main_dir/$item"

    if [[ ! -e "$source_path" ]]; then
      continue  # main doesn't have it; neither should profile
    fi

    if [[ -L "$path" ]]; then
      if is_dangling_symlink "$path"; then
        err "  $item → dangling symlink"
        errors=$((errors + 1))
      else
        ok "  $item → $(readlink "$path")"
      fi
    elif [[ -e "$path" ]]; then
      warn "  $item is a real file/dir (sharing disabled for this item)"
      warnings=$((warnings + 1))
    else
      warn "  $item exists in main but not in profile (run 'ccprofile sync $name')"
      warnings=$((warnings + 1))
    fi
  done

  # Unknown top-level items in main profile
  info ""
  info "$(bold "Unknown items in main profile")"
  local found_unknown=0
  local base
  while IFS= read -r -d '' path; do
    base=$(basename "$path")
    case "$base" in
      .|..) continue ;;
    esac
    if is_known "$base"; then continue; fi
    warn "  $base (not in shared-lists — review and update shared-lists.sh if needed)"
    found_unknown=1
    warnings=$((warnings + 1))
  done < <(find "$main_dir" -mindepth 1 -maxdepth 1 -print0 2>/dev/null)
  [[ $found_unknown -eq 0 ]] && hint "  (none)"

  # Summary
  info ""
  if [[ $errors -gt 0 ]]; then
    err "Status: UNHEALTHY ($errors errors, $warnings warnings)"
    return 1
  elif [[ $warnings -gt 0 ]]; then
    warn "Status: OK with warnings ($warnings)"
    return 0
  else
    ok "Status: HEALTHY"
    return 0
  fi
}

# Check a group of files that must stay independent (non-symlinks).
# Args: profile_dir, symlink_error_suffix, item...
# Returns: error count via exit status (capped at 255).
_check_isolated_group() {
  local profile="$1" err_suffix="$2"
  shift 2
  local errs=0 item path
  for item in "$@"; do
    path="$profile/$item"
    if [[ -L "$path" ]]; then
      err "  $item is a symlink — $err_suffix"
      errs=$((errs + 1))
    elif [[ -e "$path" ]]; then
      ok "  $item is independent"
    else
      hint "  $item does not exist yet"
    fi
  done
  return "$errs"
}
