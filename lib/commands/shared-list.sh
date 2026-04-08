# shellcheck shell=bash
# ccprofile shared-list
#
# Print the full classification of what's shared vs isolated, with source
# code evidence. Useful for audit and review.

cmd_shared_list() {
  bold "Claude Code profile file classification"
  info ""
  info "Based on source analysis of:"
  info "  src/utils/env.ts, src/utils/envUtils.ts,"
  info "  src/utils/secureStorage/, src/utils/config.ts,"
  info "  src/services/mcp/client.ts"
  info ""

  info "$(bold "✓ SHARED — toolchain config")"
  local item
  for item in "${SHARED_TOOLCHAIN[@]}"; do printf '  %s\n' "$item"; done
  info ""

  info "$(bold "✓ SHARED — generic caches")"
  for item in "${SHARED_CACHES[@]}"; do printf '  %s\n' "$item"; done
  info ""

  info "$(bold "✓ SHARED — personal work content") ${C_DIM}(opt-out via --no-share-*)${C_RESET}"
  for item in "${SHARED_PERSONAL[@]}"; do printf '  %s\n' "$item"; done
  info ""

  info "$(bold "✗ ISOLATED — account identity") ${C_DIM}(never symlink)${C_RESET}"
  for item in "${ISOLATED_IDENTITY[@]}"; do printf '  %s\n' "$item"; done
  info ""

  info "$(bold "✗ ISOLATED — auth-adjacent caches")"
  for item in "${ISOLATED_AUTH_ADJACENT[@]}"; do printf '  %s\n' "$item"; done
  info ""

  info "$(bold "✗ ISOLATED — concurrent-run state")"
  for item in "${ISOLATED_CONCURRENT[@]}"; do printf '  %s\n' "$item"; done
  info ""

  info "$(bold "− IGNORED — external (not Claude Code)") ${C_DIM}(neither shared nor isolated)${C_RESET}"
  for item in "${IGNORED_EXTERNAL[@]}"; do printf '  %s\n' "$item"; done
}
