# shellcheck shell=bash
# ccprofile init <name> [flags]
#
# Create a new Claude Code profile at ~/.claude-<name>/ with symlinks to
# ~/.claude/ for all shareable content.

cmd_init() {
  local name="" share_projects="yes" share_history="yes" share_file_history="yes"
  local dry_run="no"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --no-share-projects)     share_projects="no"; shift ;;
      --no-share-history)      share_history="no"; shift ;;
      --no-share-file-history) share_file_history="no"; shift ;;
      --dry-run)               dry_run="yes"; shift ;;
      -h|--help)               init_help; return 0 ;;
      -*)                      die "Unknown flag: $1" ;;
      *)
        [[ -z "$name" ]] || die "Multiple profile names given"
        name="$1"; shift
        ;;
    esac
  done

  [[ -n "$name" ]] || { init_help; die "Profile name required"; }
  validate_profile_name "$name"

  local main_dir profile
  main_dir=$(main_claude_dir)
  profile=$(profile_dir "$name")

  [[ -d "$main_dir" ]] || die "Main profile dir not found: $main_dir
  Run 'claude' once to create it."

  is_logged_in "$main_dir" \
    || die "Main profile is not logged in ($(profile_claude_json "$main_dir") has no oauthAccount).
  Run 'claude' and login first."

  [[ -e "$profile" ]] && die "Profile already exists: $profile
  Use 'ccprofile sync $name' to refresh, or 'ccprofile rm $name' first."

  info "Creating profile $(bold "$name") at $profile"
  if [[ "$dry_run" == "yes" ]]; then
    hint "  (dry-run — no changes)"
  else
    mkdir -p "$profile"
  fi

  local item source_path link_path created=0 skipped=0
  while IFS= read -r item; do
    source_path="$main_dir/$item"
    link_path="$profile/$item"

    if [[ ! -e "$source_path" ]]; then
      hint "  skip $item (not in main profile yet — will be picked up by 'sync')"
      skipped=$((skipped + 1))
      continue
    fi

    if [[ "$dry_run" == "yes" ]]; then
      info "  link $item"
    else
      if ensure_symlink "$source_path" "$link_path"; then
        ok "  link $item"
        created=$((created + 1))
      else
        warn "  skip $item (real file/dir exists at $link_path)"
        skipped=$((skipped + 1))
      fi
    fi
  done < <(resolve_share_list "$share_projects" "$share_history" "$share_file_history")

  info ""
  info "Created $created symlinks, skipped $skipped items."
  info ""
  info "$(bold "Next steps:")"
  info "  1. Add this alias to your shell config (~/.zshrc or ~/.bashrc):"
  info ""
  printf '       alias claude-%s=%sCLAUDE_CONFIG_DIR=~/.claude-%s command claude%s\n' \
    "$name" "'" "$name" "'"
  info ""
  hint "     Note: 'command claude' avoids NVM/path issues when upgrading Node."
  info ""
  info "  2. Reload your shell, then run: $(bold "claude-$name")"
  info "     First run will trigger the login flow for your second subscription."
  info ""
  hint "  Run 'ccprofile doctor $name' anytime to verify health."
}

init_help() {
  cat <<'EOF'
Usage: ccprofile init <name> [OPTIONS]

Create a new Claude Code profile sharing toolchain config with ~/.claude/.

Options:
  --no-share-projects      Keep projects/ independent (per-profile trust & approvals)
  --no-share-history       Keep history.jsonl independent (per-profile prompt history)
  --no-share-file-history  Keep file-history/ independent
  --dry-run                Print actions without making changes
  -h, --help               Show this help

Example:
  ccprofile init work
  ccprofile init personal --no-share-history
EOF
}
