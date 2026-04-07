# shellcheck shell=bash
# ccprofile list
#
# Scan ~/.claude and ~/.claude-* and display each profile's status.

cmd_list() {
  local home main_dir
  home=$(ccp_home)
  main_dir=$(main_claude_dir)

  local -a names=() paths=()
  if [[ -d "$main_dir" ]]; then
    names+=("default")
    paths+=("$main_dir")
  fi

  local dir base
  for dir in "$home"/.claude-*; do
    [[ -d "$dir" ]] || continue
    base=$(basename "$dir")
    names+=("${base#.claude-}")
    paths+=("$dir")
  done

  if [[ ${#names[@]} -eq 0 ]]; then
    info "No profiles found."
    hint "Run 'claude' once to create the default profile, then 'ccprofile init <name>'."
    return 0
  fi

  printf '%-12s %-30s %-14s %s\n' "NAME" "EMAIL" "STATUS" "PATH"
  printf '%-12s %-30s %-14s %s\n' "----" "-----" "------" "----"

  local i email plain_status color
  for i in "${!names[@]}"; do
    if is_logged_in "${paths[$i]}"; then
      email=$(json_get "$(profile_claude_json "${paths[$i]}")" "oauthAccount.emailAddress")
      plain_status="logged in"
      color="$C_GREEN"
    else
      email="—"
      plain_status="not logged in"
      color="$C_DIM"
    fi
    # Pad the plain status for alignment, then wrap with color codes
    # (width counting doesn't see the escape bytes).
    printf '%-12s %-30s %s%-14s%s %s\n' \
      "${names[$i]}" "$email" "$color" "$plain_status" "$C_RESET" "${paths[$i]}"
  done
}
