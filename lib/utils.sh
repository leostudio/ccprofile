# shellcheck shell=bash
#
# Shared utilities: color output, path resolution, error handling.

# ─── Color output ─────────────────────────────────────────────────────────
if [[ -t 1 ]] && [[ "${NO_COLOR:-}" != "1" ]]; then
  readonly C_RESET=$'\033[0m'
  readonly C_RED=$'\033[31m'
  readonly C_GREEN=$'\033[32m'
  readonly C_YELLOW=$'\033[33m'
  readonly C_BLUE=$'\033[34m'
  readonly C_DIM=$'\033[2m'
  readonly C_BOLD=$'\033[1m'
else
  readonly C_RESET='' C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_DIM='' C_BOLD=''
fi

info()  { printf '%s\n' "$*"; }
ok()    { printf '%s✓%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn()  { printf '%s⚠%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
err()   { printf '%s✗%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
die()   { err "$*"; exit 1; }

hint()  { printf '%s%s%s\n' "$C_DIM" "$*" "$C_RESET"; }
bold()  { printf '%s%s%s' "$C_BOLD" "$*" "$C_RESET"; }

# ─── Home override for tests ──────────────────────────────────────────────
# Tests set CCPROFILE_HOME_OVERRIDE to redirect all ~/ operations.
ccp_home() {
  printf '%s' "${CCPROFILE_HOME_OVERRIDE:-$HOME}"
}

# Path to the main claude config dir (default profile).
main_claude_dir() {
  printf '%s/.claude' "$(ccp_home)"
}

# Path to a named profile dir. $1 = profile name.
profile_dir() {
  printf '%s/.claude-%s' "$(ccp_home)" "$1"
}

# Path to the .claude.json file for a given profile dir.
#
# Asymmetry: for the DEFAULT profile (no CLAUDE_CONFIG_DIR), Claude Code
# resolves getClaudeConfigHomeDir() to $HOME, so .claude.json lives at
# $HOME/.claude.json — a SIBLING of $HOME/.claude/, not inside it.
# For named profiles (CLAUDE_CONFIG_DIR=$HOME/.claude-<name>), everything
# is flat inside the dir, so .claude.json is at $dir/.claude.json.
#
# $1 = config dir (main_claude_dir or profile_dir <name>).
profile_claude_json() {
  local dir="$1"
  if [[ "$dir" == "$(main_claude_dir)" ]]; then
    printf '%s/.claude.json' "$(ccp_home)"
  else
    printf '%s/.claude.json' "$dir"
  fi
}

# Validate a profile name: alphanumeric plus dash/underscore, not "claude".
validate_profile_name() {
  local name="$1"
  [[ -n "$name" ]] || die "Profile name cannot be empty"
  [[ "$name" == "claude" ]] && die "Profile name 'claude' is reserved (conflicts with default dir)"
  [[ "$name" =~ ^[a-zA-Z0-9_-]+$ ]] || die "Profile name must match [a-zA-Z0-9_-]+"
}

# ─── JSON reading without jq dependency ───────────────────────────────────
# Read a JSON field from a file using python3 (universally available on macOS).
# $1 = file, $2 = JSON path expression (e.g., "oauthAccount.emailAddress")
# Prints the value or nothing if missing. Returns 0 always.
json_get() {
  local file="$1" path="$2"
  [[ -f "$file" ]] || return 0
  python3 - "$file" "$path" <<'PY' 2>/dev/null || true
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    for key in sys.argv[2].split('.'):
        if data is None:
            break
        data = data.get(key) if isinstance(data, dict) else None
    if data is not None:
        print(data)
except Exception:
    pass
PY
}

# Detect whether the user has wrapped `claude` as a shell function in
# their shell config. This is a heuristic: we grep common rc files for
# an uncommented function definition. Functions (unlike aliases) survive
# `command claude`-style invocations only when the wrapper *itself* calls
# `command claude`, so users who inject proxy/mTLS/env vars via a function
# need to define new profiles as functions too — otherwise our suggested
# alias silently strips their wrapper.
#
# Prints the matching rc file path on stdout and returns 0 if detected,
# returns 1 otherwise. Respects $(ccp_home) for test overrides.
detect_claude_function_wrapper() {
  local home rc file
  home=$(ccp_home)
  for rc in .zshrc .bashrc .bash_profile .zprofile; do
    file="$home/$rc"
    [[ -f "$file" ]] || continue
    # Match uncommented lines defining `claude` as a function, either
    #   claude()  { ... }      /  claude () { ... }
    # or
    #   function claude() { } /  function claude { } /  function claude{
    if grep -qE '^[[:space:]]*(claude[[:space:]]*\(\)|function[[:space:]]+claude([[:space:]]|\{|\())' "$file" 2>/dev/null; then
      printf '%s' "$file"
      return 0
    fi
  done
  return 1
}

# Check if a claude config dir appears to have an OAuth account.
# $1 = config dir path. Returns 0 if logged in, 1 otherwise.
is_logged_in() {
  local dir="$1"
  local claude_json
  claude_json=$(profile_claude_json "$dir")
  [[ -f "$claude_json" ]] || return 1
  local email
  email=$(json_get "$claude_json" "oauthAccount.emailAddress")
  [[ -n "$email" ]]
}

# ─── Symlink helpers ──────────────────────────────────────────────────────

# Create a symlink from $2 → $1, but only if $2 does not yet exist.
# If $2 exists as a real file/dir, returns 1 (caller decides whether to error).
# If $2 is already a correct symlink, returns 0 (no-op).
# $1 = target (source of truth), $2 = link path
ensure_symlink() {
  local target="$1" link="$2"

  if [[ -L "$link" ]]; then
    local current
    current=$(readlink "$link")
    if [[ "$current" == "$target" ]]; then
      return 0
    fi
    rm -f "$link"
  elif [[ -e "$link" ]]; then
    return 1
  fi

  ln -s "$target" "$link"
}

# Is $1 a symlink pointing into $2?
# $1 = link, $2 = expected parent dir prefix
symlink_points_into() {
  local link="$1" prefix="$2"
  [[ -L "$link" ]] || return 1
  local target
  target=$(readlink "$link")
  [[ "$target" == "$prefix"/* ]] || [[ "$target" == "$prefix" ]]
}

# Is $1 a dangling symlink?
is_dangling_symlink() {
  [[ -L "$1" ]] && [[ ! -e "$1" ]]
}
