# shellcheck shell=bash
#
# File classification lists for Claude Code config directories.
#
# These lists are derived from source-code analysis of Claude Code:
#   - src/utils/env.ts              → getGlobalClaudeFile()
#   - src/utils/envUtils.ts         → getClaudeConfigHomeDir()
#   - src/utils/secureStorage/      → OAuth token storage
#   - src/utils/config.ts           → saveGlobalConfig()
#   - src/services/mcp/client.ts    → mcp-needs-auth-cache.json
#
# Each item below is either safely shareable across profiles (symlink) or
# must stay independent per profile (real file/dir).

# ─── SHARE: toolchain configuration ──────────────────────────────────────
# Always safe to share. This is the primary reason to run multiple profiles.
SHARED_TOOLCHAIN=(
  "settings.json"
  "settings.local.json"  # src/utils/settings/settings.ts:298-306 — project-local
                         # override (gitignored). Appears under ~/.claude/ only when
                         # `claude` is run from $HOME, where the project's
                         # .claude/settings.local.json coincides with the config
                         # home. Account-neutral; treat like settings.json.
  "CLAUDE.md"
  "commands"
  "skills"
  "plugins"
  "statusline-command.sh"   # Canonical filename written by `/statusline` setup agent
                            # (src/tools/AgentTool/built-in/statuslineSetup.ts:114).
  "statusline.sh"           # Common alternative name. The `statusLine` setting in
                            # settings.json is just a command path, so users / skills
                            # are free to pick any filename — `statusline.sh` is the
                            # other one we've seen in the wild. Account-neutral shell
                            # script, same treatment as statusline-command.sh.
  ".gitignore"
)

# ─── SHARE: generic caches ───────────────────────────────────────────────
# No per-account state. Sharing saves disk and avoids re-downloads.
SHARED_CACHES=(
  "cache"
  "chrome"
  "ide"
  "image-cache"  # src/utils/imageStore.ts:9,18-20 — per-session image paste cache,
                 # keyed by sessionId (UUID). Old session subdirs auto-cleaned on
                 # startup (lines 129-167). No account state.
)

# ─── SHARE: personal work content (opt-out via --no-share-*) ─────────────
# Safe to share when both profiles belong to the same person.
# Can be made independent via init flags.
SHARED_PERSONAL=(
  "projects"            # --no-share-projects     (trust, MCP approvals)
  "history.jsonl"       # --no-share-history      (prompt history)
  "file-history"        # --no-share-file-history (Edit undo snapshots)
  "paste-cache"
  "plans"
  "todos"
  "shell-snapshots"
  "session-env"
  "backups"
)

# ─── ISOLATE: account identity ────────────────────────────────────────────
# Contain oauthAccount / subscriptionType / OAuth tokens. Never symlink.
ISOLATED_IDENTITY=(
  ".claude.json"        # src/utils/env.ts:14 getGlobalClaudeFile()
  ".credentials.json"   # src/utils/secureStorage/plainTextStorage.ts:15
  "config.json"         # legacy fallback in getGlobalClaudeFile()
)

# ─── ISOLATE: auth-adjacent caches ────────────────────────────────────────
# Key finding from source-code analysis — other multi-account tools miss these.
# These caches are keyed off account/org/subscription and WILL cause
# confusing bugs if shared.
ISOLATED_AUTH_ADJACENT=(
  "stats-cache.json"          # per-account usage cache
  "statsig"                   # feature-flag bucketing by accountID
  "usage-data"                # local usage tracking
  "settings-cache.json"       # remoteManagedSettings cache
  "policyLimits-cache.json"   # policy limits cache
  "mcp-needs-auth-cache.json" # src/services/mcp/client.ts:262
  "telemetry"                 # src/services/analytics/firstPartyEventLoggingExporter.ts:44-46
                              # Retry queue for failed first-party events. Events
                              # carry account/org auth context, so sharing would
                              # cause wrong-account attribution on retry.
)

# ─── ISOLATE: concurrent-run state ────────────────────────────────────────
# PID files, locks, per-session logs. Two profiles running concurrently
# would collide if these were shared.
ISOLATED_CONCURRENT=(
  "sessions"
  "tasks"
  "debug"
  "log"
)

# ─── IGNORE: external (not Claude Code) ───────────────────────────────────
# Files/dirs that other tools (e.g. Claude Desktop) drop under ~/.claude/
# but that Claude Code itself never reads or writes. ccprofile deliberately
# does NOT manage these — it neither symlinks them (so it can't break the
# external tool) nor enforces isolation (since they have no relation to
# Claude Code's account state). They're listed here purely so `doctor`'s
# unknown-item scan stops warning about them.
IGNORED_EXTERNAL=(
  "downloads"   # Not referenced anywhere in Claude Code source. Most likely
                # written by Claude Desktop (the macOS app), which shares the
                # ~/.claude/ namespace but is otherwise unrelated.
)

# ─── Helper: resolve share list given --no-share-* flags ──────────────────
# Args:
#   $1 — "yes"/"no" for share-projects
#   $2 — "yes"/"no" for share-history
#   $3 — "yes"/"no" for share-file-history
# Prints the effective share list (one item per line).
resolve_share_list() {
  local share_projects="$1"
  local share_history="$2"
  local share_file_history="$3"

  local item
  for item in "${SHARED_TOOLCHAIN[@]}" "${SHARED_CACHES[@]}"; do
    printf '%s\n' "$item"
  done
  for item in "${SHARED_PERSONAL[@]}"; do
    case "$item" in
      projects)     [[ "$share_projects"     == "yes" ]] && printf '%s\n' "$item" ;;
      history.jsonl)[[ "$share_history"      == "yes" ]] && printf '%s\n' "$item" ;;
      file-history) [[ "$share_file_history" == "yes" ]] && printf '%s\n' "$item" ;;
      *)            printf '%s\n' "$item" ;;
    esac
  done
}

# Prints all items that MUST be independent (real files/dirs).
all_isolated_items() {
  local item
  for item in "${ISOLATED_IDENTITY[@]}" "${ISOLATED_AUTH_ADJACENT[@]}" "${ISOLATED_CONCURRENT[@]}"; do
    printf '%s\n' "$item"
  done
}

# Prints every item classified in any of the seven lists (one per line).
all_known_items() {
  local item
  for item in \
    "${SHARED_TOOLCHAIN[@]}" \
    "${SHARED_CACHES[@]}" \
    "${SHARED_PERSONAL[@]}" \
    "${ISOLATED_IDENTITY[@]}" \
    "${ISOLATED_AUTH_ADJACENT[@]}" \
    "${ISOLATED_CONCURRENT[@]}" \
    "${IGNORED_EXTERNAL[@]}"; do
    printf '%s\n' "$item"
  done
}

# is_known <item> — true if item is classified in any of the seven lists.
# Note: linear scan rather than associative-array lookup, because this project
# targets macOS's default bash 3.2 which has no associative arrays.
is_known() {
  local needle="$1" item
  for item in \
    "${SHARED_TOOLCHAIN[@]}" \
    "${SHARED_CACHES[@]}" \
    "${SHARED_PERSONAL[@]}" \
    "${ISOLATED_IDENTITY[@]}" \
    "${ISOLATED_AUTH_ADJACENT[@]}" \
    "${ISOLATED_CONCURRENT[@]}" \
    "${IGNORED_EXTERNAL[@]}"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}
