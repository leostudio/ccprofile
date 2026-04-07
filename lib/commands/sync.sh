# shellcheck shell=bash
# ccprofile sync <name>
#
# Re-resolve symlinks: create missing ones, remove dangling ones.
# Aborts on any real file in the profile that would be shadowed.

cmd_sync() {
  local name=""
  local share_projects="yes" share_history="yes" share_file_history="yes"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --no-share-projects)     share_projects="no"; shift ;;
      --no-share-history)      share_history="no"; shift ;;
      --no-share-file-history) share_file_history="no"; shift ;;
      -h|--help)
        cat <<'EOF'
Usage: ccprofile sync <name> [--no-share-*]

Re-sync a profile's symlinks against the main profile.

Creates missing symlinks for items that appeared in the main profile after
'init'. Removes dangling symlinks. Aborts on real-file collisions.

The --no-share-* flags should match what was passed to 'init', since sync
does not persist those choices.
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

  local main_dir profile
  main_dir=$(main_claude_dir)
  profile=$(profile_dir "$name")

  [[ -d "$main_dir" ]] || die "Main profile dir not found: $main_dir"
  [[ -d "$profile" ]] || die "Profile not found: $profile
  Run 'ccprofile init $name' first."

  local item source_path link_path
  local linked=0 removed=0 already=0

  local -a items=()
  while IFS= read -r item; do
    items+=("$item")
  done < <(resolve_share_list "$share_projects" "$share_history" "$share_file_history")

  local -a collisions=()
  for item in "${items[@]}"; do
    link_path="$profile/$item"
    if [[ -e "$link_path" ]] && [[ ! -L "$link_path" ]]; then
      collisions+=("$item")
    fi
  done

  if [[ ${#collisions[@]} -gt 0 ]]; then
    err "Real files/dirs found where symlinks were expected:"
    for item in "${collisions[@]}"; do
      err "  $profile/$item"
    done
    info ""
    info "Resolve manually, then re-run sync:"
    info "  - If you want to discard the profile's version:"
    info "      rm -rf $profile/<item>"
    info "  - If you want to keep it (break sharing): leave it alone and"
    info "    sync will skip it with a warning on future runs."
    exit 1
  fi

  for item in "${items[@]}"; do
    source_path="$main_dir/$item"
    link_path="$profile/$item"

    if [[ -L "$link_path" ]]; then
      if is_dangling_symlink "$link_path"; then
        rm -f "$link_path"
        ok "removed dangling: $item"
        removed=$((removed + 1))
      else
        already=$((already + 1))
      fi
      continue
    fi

    [[ -e "$source_path" ]] || continue

    if ensure_symlink "$source_path" "$link_path"; then
      ok "linked: $item"
      linked=$((linked + 1))
    fi
  done

  info ""
  info "Linked $linked, removed $removed dangling, $already already correct."
}
